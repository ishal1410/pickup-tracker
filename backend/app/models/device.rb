# One physical device, identified by its serial number. This is the unit that
# gets sanitized, gets an outcome, and appears on the certificate.
# ponytail: every device is treated as data-bearing. Add a data_bearing flag
# when monitors and peripherals come in.
class Device < ApplicationRecord
  include ForwardOnly

  STATUSES = %w[expected received not_received sanitized resold donated recycled].freeze
  OUTCOMES = %w[resold donated recycled].freeze
  FINISHED = (OUTCOMES + %w[not_received]).freeze
  SANITIZED_OR_LATER = (%w[sanitized] + OUTCOMES).freeze
  SANITIZATION_METHODS = %w[wipe destroy].freeze
  # No path skips "sanitized", so no device reaches an outcome with its data
  # intact. Outcomes and not_received have no exits.
  TRANSITIONS = {
    "expected" => %w[received not_received],
    "received" => %w[sanitized],
    "sanitized" => OUTCOMES
  }.freeze

  belongs_to :pickup
  has_many :events, -> { order(:id) }, class_name: "DeviceEvent"

  normalizes :serial_number, with: ->(serial) { serial.strip.upcase }

  validates :serial_number, presence: true, length: { maximum: 50 }
  # Matches the partial unique index: a not_received device releases its serial.
  validates :serial_number, uniqueness: { conditions: -> { where.not(status: "not_received") } },
    unless: -> { status == "not_received" }
  validates :model, length: { maximum: 100 }
  validates :status, inclusion: { in: STATUSES }
  validates :sanitization_method, inclusion: { in: SANITIZATION_METHODS }, unless: :before_sanitize?
  validates :sanitized_at, presence: true, unless: :before_sanitize?
  validate :sanitization_method_unchanged, on: :update
  validate :starts_expected_or_received, on: :create
  validate :pickup_collected_for_warehouse_steps
  validate :destroyed_device_only_recycled
  validate :pickup_open, if: -> { new_record? || (status_changed? && status == "not_received") }

  after_create { events.create!(from_status: nil, to_status: status, created_at: created_at) }

  def receive(at: Time.current)
    move_to("received", at: at)
  end

  # ADR-009: a serial the customer listed that never reached the warehouse.
  # Once the pickup is collected, Revivn knows what arrived.
  def mark_not_received
    if pickup.status == "scheduled"
      errors.add(:status, "can't be marked not received before the pickup is collected")
      return false
    end
    move_to("not_received")
  end

  def sanitize(method, at: Time.current)
    move_to("sanitized", at: at, sanitization_method: method, sanitized_at: at)
  end

  def dispose(outcome, at: Time.current)
    unless OUTCOMES.include?(outcome)
      errors.add(:status, "must be one of: #{OUTCOMES.join(', ')}")
      return false
    end
    move_to(outcome, at: at)
  end

  def as_json(_options = nil)
    {
      "id" => id,
      "pickup_id" => pickup_id,
      "serial_number" => serial_number,
      "model" => model,
      "status" => status,
      "sanitization_method" => sanitization_method,
      "sanitized_at" => sanitized_at,
      "history" => events.map { |event| { "status" => event.to_status, "at" => event.created_at } },
      "created_at" => created_at,
      "updated_at" => updated_at
    }
  end

  private
    def before_sanitize?
      %w[expected received not_received].include?(status)
    end

    def starts_expected_or_received
      errors.add(:status, "must be expected or received for a new device") unless %w[expected received].include?(status)
    end

    # Only Revivn touches a device after it leaves the customer, and only
    # once the pickup is collected.
    def pickup_collected_for_warehouse_steps
      return if %w[expected not_received].include?(status) || pickup.nil?
      errors.add(:pickup, "must be collected first") unless pickup.collected?
    end

    # ADR-010: an issued certificate is final, so the device list can't change.
    # ponytail: checked, not locked; a device added in the same instant the
    # certificate is issued could slip in. Lock the pickup row if that matters.
    def pickup_open
      number = pickup&.certificate&.number
      errors.add(:pickup, "is closed: certificate #{number} already issued") if number
    end

    # API-v2 2.3: once set it never changes.
    def sanitization_method_unchanged
      if sanitization_method_changed? && sanitization_method_was.present?
        errors.add(:sanitization_method, "can't change once set")
      end
    end

    def destroyed_device_only_recycled
      if sanitization_method == "destroy" && %w[resold donated].include?(status)
        errors.add(:status, "can only be recycled after the drive is destroyed")
      end
    end
end
