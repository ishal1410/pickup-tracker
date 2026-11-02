# The customer's proof that data was destroyed (ADR-010). Issued once by
# Pickup#issue_certificate!; its existence closes the pickup to intake.
class Certificate < ApplicationRecord
  belongs_to :pickup

  # API-v2 4.9. Devices are read live; the lock keeps the list from growing.
  def as_json(_options = nil)
    devices = pickup.devices.includes(:events).sort_by(&:serial_number)
    missing, handled = devices.partition { |device| device.status == "not_received" }
    {
      "pickup_id" => pickup.id,
      "certificate_number" => number,
      "customer_name" => pickup.customer.name,
      "pickup_date" => pickup.pickup_date,
      "standard" => "NIST SP 800-88",
      "issued_at" => issued_at,
      "devices" => handled.map do |device|
        device.as_json.slice("serial_number", "model", "sanitization_method", "sanitized_at", "status")
          .merge("received_at" => device.events.find { |event| event.to_status == "received" }&.created_at)
      end,
      "not_received_serials" => missing.map(&:serial_number)
    }
  end
end
