require "test_helper"

class CertificatesTest < ActionDispatch::IntegrationTest
  test "409 until every device is sanitized" do
    get certificate_pickup_url(pickups(:collected)), as: :json
    assert_response :conflict
    assert_equal({ "error" => "Certificate is available once every device in this pickup is sanitized" }, response.parsed_body)
  end

  test "409 for a pickup with no devices" do
    get certificate_pickup_url(pickups(:upcoming)), as: :json
    assert_response :conflict
  end

  test "lists every device once all are sanitized" do
    devices(:received_one).sanitize("wipe")

    get certificate_pickup_url(pickups(:collected)), as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal %w[customer_name devices issued_at pickup_date pickup_id standard], body.keys.sort
    assert_equal [ "Acme Corp", "NIST SP 800-88", pickups(:collected).id ], body.values_at("customer_name", "standard", "pickup_id")
    assert_equal %w[C02DES0001 C02REC0001 C02RES0001 C02WIP0001], body["devices"].map { |d| d["serial_number"] }
    assert_equal %w[model sanitization_method sanitized_at serial_number status], body["devices"].first.keys.sort
  end

  test "another customer's certificate answers 404" do
    get certificate_pickup_url(pickups(:globex_pickup)), as: :json
    assert_response :not_found
  end
end
