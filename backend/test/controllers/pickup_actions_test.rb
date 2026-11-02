require "test_helper"

class PickupActionsTest < ActionDispatch::IntegrationTest
  test "cancel a scheduled pickup" do
    post cancel_pickup_url(pickups(:upcoming)), as: :json
    assert_response :success
    assert_equal %w[cancelled cancelled], response.parsed_body.values_at("status", "progress")
  end

  test "cancel a collected pickup is refused with the reason" do
    post cancel_pickup_url(pickups(:collected)), as: :json
    assert_response :unprocessable_content
    assert_equal({ "status" => [ "can't go from collected to cancelled" ] }, response.parsed_body)
  end

  test "collect a pickup dated today" do
    post collect_pickup_url(pickups(:today)), as: :json
    assert_response :success
    assert_equal %w[collected collected], response.parsed_body.values_at("status", "progress")
    assert_equal 1, response.parsed_body["devices"].size
  end

  test "collect a future pickup is refused" do
    post collect_pickup_url(pickups(:upcoming)), as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup_date" => [ "is in the future, so the pickup can't be collected yet" ] }, response.parsed_body)
  end

  test "actions on another customer's pickup answer 404" do
    post cancel_pickup_url(pickups(:globex_pickup)), as: :json
    assert_response :not_found
    assert_equal({ "error" => "Pickup not found" }, response.parsed_body)
  end

  test "pickups can no longer be edited or deleted" do
    patch pickup_url(pickups(:today)), params: { pickup: { status: "collected" } }, as: :json
    assert_response :not_found
    delete pickup_url(pickups(:today)), as: :json
    assert_response :not_found
    assert_equal "scheduled", pickups(:today).reload.status
  end

  test "cancel releases listed serials as not_received, so they can be booked again" do
    post cancel_pickup_url(pickups(:today)), as: :json
    assert_response :success
    device = response.parsed_body["devices"].first
    assert_equal "not_received", device["status"]
    assert_equal [ "not_received" ], device["history"].map { |event| event["status"] }

    post pickups_url, params: { pickup: { pickup_date: Date.current.to_s, estimated_device_count: 1,
                                          serial_numbers: [ "C02EXP0001" ] } }, as: :json
    assert_response :created
    assert_equal %w[C02EXP0001 expected], response.parsed_body["devices"].first.values_at("serial_number", "status")
  end
end
