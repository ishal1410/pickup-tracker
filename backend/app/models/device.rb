# One physical device, identified by its serial number. This is the unit that
# gets sanitized, gets an outcome, and appears on the certificate.
# ponytail: every device is treated as data-bearing. Add a data_bearing flag
# when monitors and peripherals come in.
class Device < ApplicationRecord
  include ForwardOnly

  STATUSES = %w[expected received sanitized resold donated recycled].freeze
  OUTCOMES = %w[resold donated recycled].freeze
  SANITIZATION_METHODS = %w[wipe destroy].freeze
  # No path skips "sanitized", so no device reaches an outcome with its data
  # intact. Outcomes have no exits.
  TRANSITIONS = {
    "expected" => %w[received],
    "received" => %w[sanitized],
    "sanitized" => OUTCOMES
  }.freeze

  belongs_to :pickup

  normalizes :serial_number, with: ->(serial) { serial.strip.upcase }

  validates :serial_number, presence: true, length: { maximum: 50 }, uniqueness: true
  validates :model, length: { maximum: 100 }
  validates :status, inclusion: { in: STATUSES }
  validates :sanitization_method, inclusion: { in: SANITIZATION_METHODS }, unless: :before_sanitize?
  validates :sanitized_at, presence: true, unless: :before_sanitize?
  validate :sanitization_method_unchanged, on: :update
  validate :starts_expected_or_received, on: :create
  validate :pickup_collected_for_warehouse_steps
  validate :destroyed_device_only_recycled

  def receive
    move_to("received")
  end

  def sanitize(method)
    move_to("sanitized", sanitization_method: method, sanitized_at: Time.current)
  end

  def dispose(outcome)
    unless OUTCOMES.include?(outcome)
      errors.add(:status, "must be one of: #{OUTCOMES.join(', ')}")
      return false
    end
    move_to(outcome)
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
      "created_at" => created_at,
      "updated_at" => updated_at
    }
  end

  private
    def before_sanitize?
      %w[expected received].include?(status)
    end

    def starts_expected_or_received
      errors.add(:status, "must be expected or received for a new device") unless before_sanitize?
    end

    # Only Revivn touches a device after it leaves the customer, and only
    # once the pickup is collected.
    def pickup_collected_for_warehouse_steps
      return if status == "expected" || pickup.nil?
      errors.add(:pickup, "must be collected first") unless pickup.collected?
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
