require "test_helper"

class DemoDataTest < ActiveSupport::TestCase
  test "every sample device's history is chronological and dated on or before now" do
    acme = customers(:acme)
    DemoData.reset!(acme, sample: true)

    devices = acme.devices.includes(:events).to_a
    assert_equal 15, devices.size
    devices.each do |device|
      times = device.events.map(&:created_at)
      assert_equal times.sort, times, "#{device.serial_number} history out of order: #{device.events.map { |e| [ e.to_status, e.created_at ] }}"
      assert_operator times.last, :<=, Time.current, device.serial_number

      received = device.events.find { |event| event.to_status == "received" }&.created_at
      if received && device.sanitized_at
        assert_operator received, :<=, device.sanitized_at, "#{device.serial_number} received after sanitized"
      end
    end
  end
end
