require "test_helper"

class PickupProgressTest < ActiveSupport::TestCase
  def book(serials)
    Pickup.create(customer: customers(:acme), estimated_device_count: 3, pickup_date: Date.current, serial_numbers: serials)
  end

  test "serials at booking become expected devices, trimmed and uppercased" do
    pickup = book([ " c02new1 ", "", "C02NEW2" ])
    assert pickup.persisted?
    assert_equal %w[C02NEW1 C02NEW2], pickup.devices.order(:id).pluck(:serial_number)
    assert_equal %w[expected expected], pickup.devices.pluck(:status)
  end

  test "serials are optional" do
    assert_equal 0, book(nil).devices.count
  end

  test "a serial listed twice blocks the booking" do
    assert_no_difference("Pickup.count") do
      pickup = book(%w[C02DUP c02dup])
      assert_includes pickup.errors[:serial_numbers], "C02DUP is listed more than once"
    end
  end

  test "an already registered serial blocks the booking" do
    pickup = book(%w[C02EXP0001])
    assert_includes pickup.errors[:serial_numbers], "C02EXP0001 is already registered"
  end

  test "a serial longer than 50 characters blocks the booking" do
    pickup = book([ "A" * 51 ])
    assert_includes pickup.errors[:serial_numbers], "#{"A" * 51} is longer than 50 characters"
  end

  test "progress mirrors the stored status before collection" do
    assert_equal "scheduled", pickups(:today).progress
    pickups(:upcoming).cancel
    assert_equal "cancelled", pickups(:upcoming).progress
  end

  test "a collected pickup with only expected devices is 'collected'" do
    pickup = pickups(:today)
    pickup.collect
    assert_equal "collected", pickup.reload.progress
  end

  test "a collected pickup with devices in flight is 'processing'" do
    assert_equal "processing", pickups(:collected).progress
  end

  test "a collected pickup is 'complete' once every device has an outcome" do
    devices(:received_one).sanitize("wipe")
    Device.find(devices(:received_one).id).dispose("donated")
    devices(:wiped_one).dispose("resold")
    devices(:destroyed_one).dispose("recycled")
    assert_equal "complete", pickups(:collected).reload.progress
  end

  test "device_counts has every status plus total" do
    assert_equal({ "expected" => 0, "received" => 1, "not_received" => 0, "sanitized" => 2, "resold" => 1, "donated" => 0, "recycled" => 0, "total" => 4 },
      pickups(:collected).device_counts)
  end

  test "certificate is available only when every device is sanitized" do
    assert_not pickups(:collected).certificate_available?
    devices(:received_one).sanitize("wipe")
    assert pickups(:collected).reload.certificate_available?
  end

  test "certificate is not available for a pickup with no devices" do
    assert_not pickups(:upcoming).certificate_available?
  end

  test "as_json is the pickup summary from the contract" do
    json = pickups(:collected).as_json
    assert_equal %w[certificate_available certificate_number created_at device_counts estimated_device_count id pickup_date progress status updated_at],
      json.keys.sort
    assert_equal "processing", json["progress"]
  end

  test "as_json_with_devices adds the devices in id order" do
    json = pickups(:collected).as_json_with_devices
    assert_equal pickups(:collected).devices.order(:id).pluck(:id), json["devices"].map { |d| d["id"] }
  end

  def collected_with_one_missing
    pickup = book(%w[C02GOT1 C02MISS1])
    pickup.collect
    got, missing = pickup.devices.order(:id).to_a
    assert got.receive && got.sanitize("wipe")
    assert missing.mark_not_received
    [ pickup.reload, got ]
  end

  test "not_received counts as finished: outcomes plus not_received is 'complete'" do
    pickup, got = collected_with_one_missing
    assert_equal "processing", pickup.progress
    assert got.dispose("resold")
    assert_equal "complete", pickup.reload.progress
  end

  test "certificate covers the sanitized devices once nothing is expected or received" do
    pickup, _got = collected_with_one_missing
    assert pickup.certificate_available?
  end

  test "no certificate when nothing was sanitized, even if nothing is left to process" do
    pickup = book(%w[C02MISS2])
    pickup.collect
    assert pickup.devices.first.mark_not_received
    assert_not pickup.reload.certificate_available?
  end
end
