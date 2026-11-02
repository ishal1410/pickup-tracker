require "test_helper"

class DeviceTest < ActiveSupport::TestCase
  test "fixtures are valid" do
    Device.all.each { |device| assert device.valid?, device.serial_number }
  end

  test "serial is trimmed and uppercased" do
    assert_equal "C02ABC", Device.new(serial_number: "  c02abc ").serial_number
  end

  test "serial is required, unique and at most 50 characters" do
    device = pickups(:collected).devices.new(status: "received", serial_number: "")
    assert_not device.valid?
    device.serial_number = "c02rec0001"
    assert_not device.valid?
    assert_includes device.errors[:serial_number], "has already been taken"
    device.serial_number = "X" * 51
    assert_not device.valid?
  end

  test "a new device starts expected or received" do
    device = pickups(:collected).devices.new(serial_number: "NEW1", status: "sanitized", sanitization_method: "wipe")
    assert_not device.valid?
    assert_includes device.errors[:status], "must be expected or received for a new device"
  end

  test "a received device needs a collected pickup" do
    device = pickups(:today).devices.new(serial_number: "NEW2", status: "received")
    assert_not device.valid?
    assert_includes device.errors[:pickup], "must be collected first"
  end

  test "receive is refused while the pickup is still scheduled" do
    device = devices(:expected_one)
    assert_not device.receive
    assert_includes device.errors[:pickup], "must be collected first"
  end

  test "receive works once the pickup is collected" do
    assert pickups(:today).collect
    device = Device.find(devices(:expected_one).id)
    assert device.receive
    assert_equal "received", device.reload.status
  end

  test "sanitize records the method and the time" do
    device = devices(:received_one)
    assert device.sanitize("wipe")
    device.reload
    assert_equal %w[sanitized wipe], [ device.status, device.sanitization_method ]
    assert_not_nil device.sanitized_at
  end

  test "a move can be backdated: at: stamps the history entry and sanitized_at" do
    device = devices(:received_one)
    at = Time.zone.parse("2026-01-05 14:00")
    assert device.sanitize("wipe", at: at)
    device.reload
    assert_equal at, device.sanitized_at
    assert_equal at, device.events.last.created_at
    assert_equal "sanitized", device.events.last.to_status
  end

  test "sanitize rejects an unknown method" do
    device = devices(:received_one)
    assert_not device.sanitize("melt")
    assert_includes device.errors[:sanitization_method], "is not included in the list"
  end

  test "sanitizing twice is refused, so the method can't be swapped" do
    device = devices(:destroyed_one)
    assert_not device.sanitize("wipe")
    assert_includes device.errors[:status], "can't go from sanitized to sanitized"
    assert_equal "destroy", device.reload.sanitization_method
  end

  test "a concurrent second sanitize from a stale copy is refused, not overwritten" do
    first = Device.find(devices(:received_one).id)
    stale = Device.find(devices(:received_one).id)
    assert first.sanitize("wipe")

    assert_not stale.sanitize("destroy")
    assert_equal({ status: [ "can't go from sanitized to sanitized" ] }, stale.errors.to_hash)
    assert_equal "wipe", Device.find(first.id).sanitization_method
  end

  test "a sanitized device needs sanitized_at, even through a direct update" do
    device = devices(:received_one)
    assert_not device.update(status: "sanitized", sanitization_method: "wipe")
    assert_equal({ sanitized_at: [ "can't be blank" ] }, device.errors.to_hash)
  end

  test "the sanitization method can't change once set, even through a direct update" do
    device = devices(:wiped_one)
    assert_not device.update(sanitization_method: "destroy")
    assert_equal({ sanitization_method: [ "can't change once set" ] }, device.errors.to_hash)
  end

  test "compliance: no outcome before sanitize" do
    device = devices(:received_one)
    assert_not device.dispose("resold")
    assert_includes device.errors[:status], "can't go from received to resold"
    assert_equal "received", device.reload.status
  end

  test "a wiped device can be donated" do
    assert devices(:wiped_one).dispose("donated")
    assert_equal "donated", devices(:wiped_one).reload.status
  end

  test "a destroyed device can only be recycled" do
    device = devices(:destroyed_one)
    assert_not device.dispose("resold")
    assert_includes device.errors[:status], "can only be recycled after the drive is destroyed"
    assert_not Device.find(device.id).dispose("donated")
    assert Device.find(device.id).dispose("recycled")
  end

  test "outcomes are final" do
    device = devices(:resold_one)
    assert_not device.dispose("donated")
    assert_includes device.errors[:status], "can't go from resold to donated"
  end

  test "dispose rejects a value that is not an outcome" do
    device = devices(:wiped_one)
    assert_not device.dispose("sanitized")
    assert_includes device.errors[:status], "must be one of: resold, donated, recycled"
  end

  test "no backward moves through a direct update" do
    device = devices(:wiped_one)
    assert_not device.update(status: "received")
    assert_includes device.errors[:status], "can't go from sanitized to received"
  end

  test "as_json exposes exactly the contract fields" do
    assert_equal %w[created_at history id model pickup_id sanitization_method sanitized_at serial_number status updated_at],
      devices(:received_one).as_json.keys.sort
  end

  test "database refuses a sanitized device without sanitized_at, even without validations" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Device.insert_all([ { pickup_id: pickups(:collected).id, serial_number: "RAW2", status: "sanitized",
                            sanitization_method: "wipe", sanitized_at: nil,
                            created_at: Time.current, updated_at: Time.current } ])
    end
  end

  test "database refuses a reused device whose drive was destroyed, even without validations" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Device.insert_all([ { pickup_id: pickups(:collected).id, serial_number: "RAW1", status: "resold",
                            sanitization_method: "destroy", sanitized_at: Time.current,
                            created_at: Time.current, updated_at: Time.current } ])
    end
  end

  test "a listed serial that never arrived is marked not_received, and stays there" do
    assert pickups(:today).collect
    device = Device.find(devices(:expected_one).id)
    assert device.mark_not_received
    assert_equal "not_received", device.reload.status
    assert_not device.receive
    assert_includes device.errors[:status], "can't go from not_received to received"
  end

  test "only an expected device can be marked not_received" do
    device = devices(:received_one)
    assert_not device.mark_not_received
    assert_equal({ status: [ "can't go from received to not_received" ] }, device.errors.to_hash)
  end

  test "mark_not_received needs a collected pickup" do
    device = devices(:expected_one)
    assert_not device.mark_not_received
    assert_equal({ status: [ "can't be marked not received before the pickup is collected" ] }, device.errors.to_hash)
    assert_equal "expected", device.reload.status
  end

  test "history records creation and every move, oldest first" do
    device = pickups(:collected).devices.create!(serial_number: "HIST1", status: "received")
    assert device.sanitize("wipe")
    assert device.dispose("recycled")

    history = device.reload.as_json["history"]
    assert_equal %w[received sanitized recycled], history.map { |event| event["status"] }
    assert_equal %w[at status], history.first.keys.sort
    assert history.all? { |event| event["at"].present? }
    assert_equal [ nil, "received", "sanitized" ], device.events.map(&:from_status)
  end

  test "a refused move leaves no history" do
    device = devices(:received_one)
    assert_no_difference("DeviceEvent.count") { assert_not device.dispose("resold") }
  end

  test "history is append-only" do
    device = pickups(:collected).devices.create!(serial_number: "HIST2", status: "received")
    assert_raises(ActiveRecord::ReadOnlyRecord) { device.events.first.update!(to_status: "recycled") }
  end

  test "a not_received serial can be checked in again on another pickup" do
    assert pickups(:today).cancel
    device = pickups(:collected).devices.new(serial_number: "C02EXP0001", status: "received")
    assert device.save, device.errors.full_messages.to_sentence
  end

  test "database: serials are unique among devices that are not not_received" do
    row = { pickup_id: pickups(:collected).id, serial_number: "C02REC0001", status: "not_received",
            created_at: Time.current, updated_at: Time.current }
    assert_difference("Device.count", 1) { Device.insert_all!([ row ]) }
    assert_raises(ActiveRecord::RecordNotUnique) { Device.insert_all!([ row.merge(status: "received") ]) }
  end
end
