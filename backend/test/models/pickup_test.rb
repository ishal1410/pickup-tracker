require "test_helper"

class PickupTest < ActiveSupport::TestCase
  def new_pickup(**attrs)
    Pickup.new({ customer: customers(:acme), estimated_device_count: 3, pickup_date: Date.current }.merge(attrs))
  end

  test "fixtures are valid" do
    %i[today upcoming collected globex_pickup].each { |name| assert pickups(name).valid?, name }
  end

  test "a new pickup starts scheduled" do
    assert_equal "scheduled", new_pickup.status
    assert new_pickup.valid?
  end

  test "status can't be set on create" do
    pickup = new_pickup(status: "collected")
    assert_not pickup.valid?
    assert_includes pickup.errors[:status], "must be scheduled for a new pickup"
  end

  test "estimate must be a whole number from 1 to 10,000" do
    [ 0, 10_001, 2.5, nil ].each do |bad|
      assert_not new_pickup(estimated_device_count: bad).valid?, bad.inspect
    end
    assert new_pickup(estimated_device_count: 10_000).valid?
  end

  test "requires a pickup date" do
    pickup = new_pickup(pickup_date: nil)
    assert_not pickup.valid?
    assert_includes pickup.errors[:pickup_date], "can't be blank"
  end

  test "rejects a past date on create" do
    pickup = new_pickup(pickup_date: Date.current - 1)
    assert_not pickup.valid?
    assert_includes pickup.errors[:pickup_date], "can't be in the past"
  end

  test "rejects an unknown status" do
    pickup = pickups(:today)
    pickup.status = "lost"
    assert_not pickup.valid?
  end

  test "collect moves a scheduled pickup dated today to collected" do
    pickup = pickups(:today)
    assert pickup.collect
    assert_equal "collected", pickup.reload.status
  end

  test "can't collect before the pickup date" do
    pickup = pickups(:upcoming)
    assert_not pickup.collect
    assert_includes pickup.errors[:pickup_date], "is in the future, so the pickup can't be collected yet"
    assert_equal "scheduled", pickup.reload.status
  end

  test "cancel works only while scheduled" do
    assert pickups(:upcoming).cancel
    collected = pickups(:collected)
    assert_not collected.cancel
    assert_includes collected.errors[:status], "can't go from collected to cancelled"
  end

  test "cancelling twice is rejected" do
    pickup = pickups(:upcoming)
    assert pickup.cancel
    assert_not pickup.cancel
    assert_includes pickup.errors[:status], "can't go from cancelled to cancelled"
  end

  test "status can't move backward through a direct update" do
    pickup = pickups(:collected)
    assert_not pickup.update(status: "scheduled")
    assert_includes pickup.errors[:status], "can't go from collected to scheduled"
  end

  test "certificate lists the customer, the standard and every device by serial" do
    devices(:received_one).sanitize("wipe")
    cert = Pickup.find(pickups(:collected).id).certificate

    assert_equal [ pickups(:collected).id, "Acme Corp", "NIST SP 800-88" ], cert.values_at(:pickup_id, :customer_name, :standard)
    assert_equal %w[C02DES0001 C02REC0001 C02RES0001 C02WIP0001], cert[:devices].map { |d| d["serial_number"] }
    assert_equal({ "serial_number" => "C02DES0001", "model" => nil, "sanitization_method" => "destroy", "status" => "sanitized" },
      cert[:devices].first.except("sanitized_at"))
  end

  test "database rejects an unknown status even when validations are skipped" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Pickup.insert_all([ { customer_id: customers(:acme).id, estimated_device_count: 1, pickup_date: Date.current,
                            status: "lost", created_at: Time.current, updated_at: Time.current } ])
    end
  end
end
