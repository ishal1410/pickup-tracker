class Pickup < ApplicationRecord
  include ForwardOnly

  # ponytail: string column + inclusion, not enum: readable SQL and check constraints (Device does the same); switch to enum validate: true if scopes are needed.
  STATUSES = %w[scheduled collected cancelled].freeze
  # Only these moves are stored. "processing" and "complete" are derived
  # from the devices (see #progress), so they can never disagree.
  TRANSITIONS = { "scheduled" => %w[collected cancelled] }.freeze

  belongs_to :customer
  has_many :devices
  has_one :certificate

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
  # Listed serials that will never arrive become not_received (audited by
  # move_to), which releases them for a new booking.
  def cancel
    transaction do
      next false unless move_to("cancelled")
      devices.where(status: "expected").each do |device|
        device.mark_not_received or raise ActiveRecord::RecordInvalid, device
      end
      true
    end
  end

  def collected?
    status == "collected"
  end

  # Optional at booking: trimmed, uppercased, blank lines dropped.
  def serial_numbers=(list)
    @serial_numbers = Array(list).map { |serial| serial.to_s.strip.upcase }.reject(&:empty?)
  end

  # The list endpoint counts every pickup's devices in one grouped query
  # instead of loading the rows.
  def self.with_device_counts(pickups)
    pickups = pickups.to_a
    counts = Device.where(pickup: pickups).group(:pickup_id, :status).count
    pickups.each do |pickup|
      pickup.device_counts = Device::STATUSES.index_with { |status| counts.fetch([ pickup.id, status ], 0) }
    end
  end

  def device_counts=(by_status)
    @device_counts = by_status.merge("total" => by_status.values.sum)
  end

  def device_counts
    @device_counts || begin
      tally = devices.map(&:status).tally
      Device::STATUSES.index_with { |status| tally.fetch(status, 0) }.merge("total" => tally.values.sum)
    end
  end

  def progress
    return status unless collected?

    counts = device_counts
    return "complete" if counts["total"].positive? && Device::FINISHED.sum { |status| counts[status] } == counts["total"]
    return "processing" if counts["expected"] < counts["total"]
    "collected"
  end

  # Every status from sanitized on carries sanitized_at (validation plus the
  # devices_sanitized_fields check constraint), so the counts answer this.
  # not_received devices don't block it; they're listed apart on the certificate.
  def certificate_available?
    counts = device_counts
    collected? && counts["expected"].zero? && counts["received"].zero? &&
      Device::SANITIZED_OR_LATER.sum { |status| counts[status] }.positive?
  end

  # API-v2 4.9: issued on first request, then the stored one is returned.
  # create_or_find_by! leans on the unique pickup_id index, so two requests
  # racing here still end with one certificate.
  # ponytail: the number comes from the pickup id, so it is known before the insert.
  def issue_certificate!
    certificate || Certificate.create_or_find_by!(pickup: self) do |cert|
      cert.number = format("CERT-%06d", id)
      cert.issued_at = Time.current
    end
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
      "certificate_number" => certificate&.number,
      "created_at" => created_at,
      "updated_at" => updated_at
    }
  end

  # API-v2 3.2: the summary plus devices, in booking then intake order.
  def as_json_with_devices
    as_json.merge("devices" => devices.includes(:events).order(:id).map(&:as_json))
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
      Device.where(serial_number: serials).where.not(status: "not_received").pluck(:serial_number).each { |serial| errors.add(:serial_numbers, "#{serial} is already registered") }
    end

    # A concurrent booking can register a serial after serial_numbers_valid ran.
    # The device insert then fails its validation or the unique index; report it
    # like the normal check. Raising RecordInvalid makes save roll back and return false.
    def create_expected_devices
      Array(serial_numbers).each do |serial|
        devices.create!(serial_number: serial, status: "expected", created_at: created_at)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
        errors.add(:serial_numbers, "#{serial} is already registered")
        raise ActiveRecord::RecordInvalid, self
      end
    end
end
