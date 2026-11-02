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
end
