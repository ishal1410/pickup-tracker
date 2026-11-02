require "test_helper"

class DevicesControllerTest < ActionDispatch::IntegrationTest
  def device_json(id)
    response.parsed_body["devices"].find { |d| d["id"] == id }
  end

  test "warehouse adds an unlisted device to a collected pickup" do
    assert_difference("Device.count", 1) do
      post pickup_devices_url(pickups(:collected)), params: { device: { serial_number: " dmpx1 ", model: "iPad Air" } }, as: :json
    end
    assert_response :created
    added = response.parsed_body["devices"].last
    assert_equal [ "DMPX1", "iPad Air", "received" ], added.values_at("serial_number", "model", "status")
  end

  test "adding a device to a scheduled pickup is refused" do
    post pickup_devices_url(pickups(:today)), params: { device: { serial_number: "NEW9" } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup" => [ "must be collected first" ] }, response.parsed_body)
  end

  test "adding a duplicate serial is refused" do
    post pickup_devices_url(pickups(:collected)), params: { device: { serial_number: "C02REC0001" } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "serial_number" => [ "has already been taken" ] }, response.parsed_body)
  end

  test "a duplicate serial that races past the validation still answers 422" do
    # As if a concurrent insert landed between the validation and ours: only the unique index fires.
    validator = Device.validators_on(:serial_number).grep(ActiveRecord::Validations::UniquenessValidator).first
    validator.define_singleton_method(:validate_each) { |*| }

    post pickup_devices_url(pickups(:collected)), params: { device: { serial_number: "C02REC0001" } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "serial_number" => [ "has already been taken" ] }, response.parsed_body)
  ensure
    validator.singleton_class.remove_method(:validate_each)
  end

  test "receive an expected device once the pickup is collected" do
    pickups(:today).collect
    post receive_device_url(devices(:expected_one)), as: :json
    assert_response :success
    assert_equal "received", device_json(devices(:expected_one).id)["status"]
    assert_equal "processing", response.parsed_body["progress"]
  end

  test "receive while the pickup is scheduled is refused" do
    post receive_device_url(devices(:expected_one)), as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup" => [ "must be collected first" ] }, response.parsed_body)
  end

  test "sanitize by wipe" do
    post sanitize_device_url(devices(:received_one)), params: { sanitization_method: "wipe" }, as: :json
    assert_response :success
    device = device_json(devices(:received_one).id)
    assert_equal %w[sanitized wipe], device.values_at("status", "sanitization_method")
    assert device["sanitized_at"].present?
  end

  test "sanitize with an unknown method is refused" do
    post sanitize_device_url(devices(:received_one)), params: { sanitization_method: "melt" }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "sanitization_method" => [ "is not included in the list" ] }, response.parsed_body)
  end

  test "dispose before sanitize is refused" do
    post dispose_device_url(devices(:received_one)), params: { outcome: "resold" }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "status" => [ "can't go from received to resold" ] }, response.parsed_body)
  end

  test "a destroyed device can't be resold but can be recycled" do
    post dispose_device_url(devices(:destroyed_one)), params: { outcome: "resold" }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "status" => [ "can only be recycled after the drive is destroyed" ] }, response.parsed_body)

    post dispose_device_url(devices(:destroyed_one)), params: { outcome: "recycled" }, as: :json
    assert_response :success
  end

  test "the last outcome completes the pickup" do
    post sanitize_device_url(devices(:received_one)), params: { sanitization_method: "wipe" }, as: :json
    post dispose_device_url(devices(:received_one)), params: { outcome: "donated" }, as: :json
    post dispose_device_url(devices(:wiped_one)), params: { outcome: "resold" }, as: :json
    post dispose_device_url(devices(:destroyed_one)), params: { outcome: "recycled" }, as: :json
    assert_response :success
    assert_equal "complete", response.parsed_body["progress"]
    assert response.parsed_body["certificate_available"]
  end

  test "another customer's device answers 404" do
    post receive_device_url(devices(:globex_device)), as: :json
    assert_response :not_found
    assert_equal({ "error" => "Device not found" }, response.parsed_body)
  end

  test "mark a listed serial not received once the pickup is collected" do
    pickups(:today).collect
    post mark_not_received_device_url(devices(:expected_one)), as: :json
    assert_response :success
    assert_equal "not_received", device_json(devices(:expected_one).id)["status"]
    assert_equal 1, response.parsed_body["device_counts"]["not_received"]
  end

  test "mark not received on a scheduled pickup is refused" do
    post mark_not_received_device_url(devices(:expected_one)), as: :json
    assert_response :unprocessable_content
    assert_equal({ "status" => [ "can't be marked not received before the pickup is collected" ] }, response.parsed_body)
  end

  test "every action returns each device's history" do
    pickups(:today).collect
    post receive_device_url(devices(:expected_one)), as: :json
    assert_equal [ "received" ], device_json(devices(:expected_one).id)["history"].map { |event| event["status"] }
  end
end
