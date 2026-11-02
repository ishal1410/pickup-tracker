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
    assert_equal %w[certificate_number customer_name devices issued_at not_received_serials pickup_date pickup_id standard], body.keys.sort
    assert_equal [ "Acme Corp", "NIST SP 800-88", pickups(:collected).id ], body.values_at("customer_name", "standard", "pickup_id")
    assert_equal %w[C02DES0001 C02REC0001 C02RES0001 C02WIP0001], body["devices"].map { |d| d["serial_number"] }
    assert_equal %w[model received_at sanitization_method sanitized_at serial_number status], body["devices"].first.keys.sort
  end

  test "another customer's certificate answers 404" do
    get certificate_pickup_url(pickups(:globex_pickup)), as: :json
    assert_response :not_found
  end

  def cert_number(pickup)
    format("CERT-%06d", pickup.id)
  end

  test "issued once: number and issued_at are stored and stable across reads" do
    devices(:received_one).sanitize("wipe")
    pickup = pickups(:collected)

    travel_to Time.zone.local(2026, 11, 2, 10, 0) do
      assert_difference("Certificate.count", 1) { get certificate_pickup_url(pickup), as: :json }
    end
    first = response.parsed_body
    travel_to Time.zone.local(2026, 11, 3, 10, 0) do
      assert_no_difference("Certificate.count") { get certificate_pickup_url(pickup), as: :json }
    end

    assert_equal cert_number(pickup), first["certificate_number"]
    assert_equal Time.zone.local(2026, 11, 2, 10, 0), Time.zone.parse(first["issued_at"])
    assert_equal first.values_at("certificate_number", "issued_at"), response.parsed_body.values_at("certificate_number", "issued_at")
  end

  test "not_received serials are listed apart; devices carry received_at" do
    pickup = Pickup.create!(customer: customers(:acme), estimated_device_count: 2, pickup_date: Date.current,
                            serial_numbers: %w[C02GOT9 C02MISS9])
    pickup.collect
    got, missing = pickup.devices.order(:id).to_a
    got.receive && got.sanitize("destroy")
    missing.mark_not_received

    get certificate_pickup_url(pickup), as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal [ "C02GOT9" ], body["devices"].map { |d| d["serial_number"] }
    assert_equal [ "C02MISS9" ], body["not_received_serials"]
    assert body["devices"].first["received_at"].present?
  end

  test "the pickup summary carries the certificate number once issued" do
    devices(:received_one).sanitize("wipe")
    get pickup_url(pickups(:collected)), as: :json
    assert_nil response.parsed_body["certificate_number"]

    get certificate_pickup_url(pickups(:collected)), as: :json
    get pickups_url, as: :json
    summary = response.parsed_body.find { |p| p["id"] == pickups(:collected).id }
    assert_equal cert_number(pickups(:collected)), summary["certificate_number"]
  end

  test "once a certificate is issued, intake is closed" do
    devices(:received_one).sanitize("wipe")
    get certificate_pickup_url(pickups(:collected)), as: :json

    assert_no_difference("Device.count") do
      post pickup_devices_url(pickups(:collected)), params: { device: { serial_number: "LATE1" } }, as: :json
    end
    assert_response :unprocessable_content
    assert_equal({ "pickup" => [ "is closed: certificate #{cert_number(pickups(:collected))} already issued" ] }, response.parsed_body)
  end

  test "once a certificate is issued, mark not received is refused too" do
    pickups(:today).collect
    pickups(:today).create_certificate!(number: cert_number(pickups(:today)), issued_at: Time.current)

    post mark_not_received_device_url(devices(:expected_one)), as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup" => [ "is closed: certificate #{cert_number(pickups(:today))} already issued" ] }, response.parsed_body)
  end
end
