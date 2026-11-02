class Pickup < ApplicationRecord
  include ForwardOnly

  STATUSES = %w[scheduled collected cancelled].freeze
  # Only these moves are stored. "processing" and "complete" are derived
  # from the devices (see #progress), so they can never disagree.
  TRANSITIONS = { "scheduled" => %w[collected cancelled] }.freeze

  belongs_to :customer
  has_many :devices

  attr_reader :serial_numbers

  validates :estimated_device_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :pickup_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :starts_scheduled, on: :create
  validate :pickup_date_not_in_past, on: :create
  validate :serial_numbers_valid, on: :create
  validate :not_collected_before_pickup_date

  after_create :create_expected_devices

  def collect
    move_to("collected")
  end

  # The customer's only change after booking. Nothing is ever deleted.
  def cancel
    move_to("cancelled")
  end

  def collected?
    status == "collected"
  end

  # Optional at booking: trimmed, uppercased, blank lines dropped.
  def serial_numbers=(list)
    @serial_numbers = Array(list).map { |serial| serial.to_s.strip.upcase }.reject(&:empty?)
  end

  def progress
    return status unless collected?

    list = devices.to_a
    return "complete" if list.any? && list.all? { |device| Device::OUTCOMES.include?(device.status) }
    return "processing" if list.any? { |device| device.status != "expected" }
    "collected"
  end

  def certificate_available?
    list = devices.to_a
    list.any? && list.all? { |device| device.sanitized_at.present? }
  end

  def device_counts
    list = devices.to_a
    Device::STATUSES.index_with { |status| list.count { |device| device.status == status } }.merge("total" => list.size)
  end

  # API-v2 3.1: the pickup summary.
  def as_json(_options = nil)
    {
      "id" => id,
      "pickup_date" => pickup_date,
      "estimated_device_count" => estimated_device_count,
      "status" => status,
      "progress" => progress,
      "device_counts" => device_counts,
      "certificate_available" => certificate_available?,
      "created_at" => created_at,
      "updated_at" => updated_at
    }
  end

  # API-v2 3.2: the summary plus devices, in booking then intake order.
  def as_json_with_devices
    as_json.merge("devices" => devices.sort_by(&:id).map(&:as_json))
  end

  private
    def starts_scheduled
      errors.add(:status, "must be scheduled for a new pickup") unless status == "scheduled"
    end

    def pickup_date_not_in_past
      errors.add(:pickup_date, "can't be in the past") if pickup_date && pickup_date < Date.current
    end

    def not_collected_before_pickup_date
      return unless status_changed? && status == "collected" && pickup_date
      errors.add(:pickup_date, "is in the future, so the pickup can't be collected yet") if pickup_date > Date.current
    end

    # ponytail: serials are unique across all customers because a physical
    # device exists once. The message reveals that a serial exists elsewhere;
    # scope it per customer if that matters.
    def serial_numbers_valid
      serials = Array(serial_numbers)
      serials.tally.each { |serial, count| errors.add(:serial_numbers, "#{serial} is listed more than once") if count > 1 }
      serials.select { |serial| serial.length > 50 }.each { |serial| errors.add(:serial_numbers, "#{serial} is longer than 50 characters") }
      Device.where(serial_number: serials).pluck(:serial_number).each { |serial| errors.add(:serial_numbers, "#{serial} is already registered") }
    end

    def create_expected_devices
      Array(serial_numbers).each { |serial| devices.create!(serial_number: serial, status: "expected") }
    end
end
