require "test_helper"

class PickupsControllerTest < ActionDispatch::IntegrationTest
  SUMMARY_KEYS = %w[certificate_available created_at device_counts estimated_device_count id pickup_date progress status updated_at].freeze

  test "index lists only the current customer's pickups" do
    get pickups_url, as: :json
    assert_response :success
    ids = response.parsed_body.map { |p| p["id"] }
    assert_includes ids, pickups(:today).id
    assert_not_includes ids, pickups(:globex_pickup).id
  end

  test "index puts the newest pickup date first" do
    get pickups_url, as: :json
    dates = response.parsed_body.map { |p| p["pickup_date"] }
    assert_equal dates.sort.reverse, dates
    assert_equal pickups(:upcoming).id, response.parsed_body.first["id"]
  end

  test "index uses the summary shape, without devices" do
    get pickups_url, as: :json
    assert_equal SUMMARY_KEYS, response.parsed_body.first.keys.sort
  end

  test "index keeps the 200 most recent pickups, so upcoming ones are never cut off" do
    now = Time.current
    old = Array.new(205) do |i|
      { customer_id: customers(:acme).id, estimated_device_count: 1, pickup_date: Date.current - 400 - i,
        status: "collected", created_at: now, updated_at: now }
    end
    Pickup.insert_all(old)

    get pickups_url, as: :json
    assert_equal 200, response.parsed_body.size
    assert_equal pickups(:upcoming).id, response.parsed_body.first["id"]
  end

  test "show returns the detail shape with devices" do
    get pickup_url(pickups(:collected)), as: :json
    assert_response :success
    assert_equal (SUMMARY_KEYS + [ "devices" ]).sort, response.parsed_body.keys.sort
    assert_equal 4, response.parsed_body["devices"].size
    assert_equal "processing", response.parsed_body["progress"]
  end

  test "show hides another customer's pickup behind a 404" do
    get pickup_url(pickups(:globex_pickup)), as: :json
    assert_response :not_found
    assert_equal({ "error" => "Pickup not found" }, response.parsed_body)
  end

  test "create books a scheduled pickup with expected devices" do
    assert_difference({ "Pickup.count" => 1, "Device.count" => 2 }) do
      post pickups_url, params: { pickup: { pickup_date: Date.current.to_s, estimated_device_count: "2",
                                            serial_numbers: [ "c02a1", "C02A2" ] } }, as: :json
    end
    assert_response :created
    body = response.parsed_body
    assert_equal %w[scheduled scheduled], body.values_at("status", "progress")
    assert_equal %w[C02A1 C02A2], body["devices"].map { |d| d["serial_number"] }
    assert_equal customers(:acme).id, Pickup.find(body["id"]).customer_id
  end

  test "create ignores a status sent by the client" do
    post pickups_url, params: { pickup: { pickup_date: Date.current.to_s, estimated_device_count: 1, status: "collected" } }, as: :json
    assert_response :created
    assert_equal "scheduled", response.parsed_body["status"]
  end

  test "create with missing fields returns 422 keyed by field" do
    post pickups_url, params: { pickup: { pickup_date: "", estimated_device_count: "" } }, as: :json
    assert_response :unprocessable_content
    assert_equal %w[estimated_device_count pickup_date], response.parsed_body.keys.sort
  end

  test "create rejects a past date" do
    post pickups_url, params: { pickup: { pickup_date: (Date.current - 1).to_s, estimated_device_count: 1 } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup_date" => [ "can't be in the past" ] }, response.parsed_body)
  end

  test "create rejects a serial that is already registered" do
    post pickups_url, params: { pickup: { pickup_date: Date.current.to_s, estimated_device_count: 1,
                                          serial_numbers: [ "C02EXP0001" ] } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "serial_numbers" => [ "C02EXP0001 is already registered" ] }, response.parsed_body)
  end

  test "create without a pickup key returns 400 JSON" do
    post pickups_url, params: {}, as: :json
    assert_response :bad_request
    assert response.parsed_body["error"].present?
  end

  test "create with fields but no pickup key is still a 400, not a booking" do
    assert_no_difference("Pickup.count") do
      post pickups_url, params: { pickup_date: Date.current.to_s, estimated_device_count: 1 }, as: :json
    end
    assert_response :bad_request
  end
end
