require "test_helper"

class DemoControllerTest < ActionDispatch::IntegrationTest
  test "reset without sample empties only the current customer's data" do
    globex_pickups = customers(:globex).pickups.count
    globex_devices = customers(:globex).devices.count

    post demo_reset_url, params: { sample: false }, as: :json

    assert_response :success
    assert_equal({ "customer" => { "id" => customers(:acme).id, "name" => "Acme Corp" }, "pickups_count" => 0 },
      response.parsed_body)
    assert_equal 0, customers(:acme).pickups.count
    assert_equal 0, customers(:acme).devices.count
    assert_equal globex_pickups, customers(:globex).pickups.count
    assert_equal globex_devices, customers(:globex).devices.count
  end

  test "missing sample means empty" do
    post demo_reset_url, as: :json
    assert_response :success
    assert_equal 0, response.parsed_body["pickups_count"]
  end

  test "sample true rebuilds 6 pickups and 15 devices" do
    post demo_reset_url, params: { sample: true }, as: :json

    assert_response :success
    assert_equal 6, response.parsed_body["pickups_count"]
    get pickups_url, as: :json
    assert_equal 6, response.parsed_body.size
    assert_equal 15, customers(:acme).devices.count
    assert_operator customers(:globex).pickups.count, :>, 0
  end

  # ponytail: minitest 6 dropped #stub, so flip Rails.env / ENV and restore them.
  def as_production(env = {})
    original, Rails.env = Rails.env, "production"
    env.each { |key, value| ENV[key] = value }
    yield
  ensure
    Rails.env = original
    env.each_key { |key| ENV.delete(key) }
  end

  test "answers 404 in production without DEMO_MODE" do
    ENV.delete("DEMO_MODE")
    as_production { post demo_reset_url, params: { sample: true }, as: :json }
    assert_response :not_found
    assert_equal({ "error" => "Not found" }, response.parsed_body)
    assert_operator customers(:acme).pickups.count, :>, 0
  end

  test "works in production when DEMO_MODE=1 (the hosted demo)" do
    as_production("DEMO_MODE" => "1") { post demo_reset_url, params: { sample: false }, as: :json }
    assert_response :success
    assert_equal 0, customers(:acme).pickups.count
  end

  test "DEMO_MODE other than 1 still answers 404 in production" do
    as_production("DEMO_MODE" => "true") { post demo_reset_url, params: { sample: false }, as: :json }
    assert_response :not_found
  end

  test "DEMO_RESET_DISABLED wins over DEMO_MODE" do
    as_production("DEMO_MODE" => "1", "DEMO_RESET_DISABLED" => "1") { post demo_reset_url, params: { sample: false }, as: :json }
    assert_response :not_found
    assert_operator customers(:acme).pickups.count, :>, 0
  end

  test "reset clears devices that have history and certificates" do
    post demo_reset_url, params: { sample: true }, as: :json
    complete = customers(:acme).pickups.order(:pickup_date).first
    get certificate_pickup_url(complete), as: :json
    assert_response :success

    post demo_reset_url, params: { sample: false }, as: :json
    assert_response :success
    assert_equal 0, customers(:acme).devices.count
  end

  test "reset needs a JSON body: a form post answers 415 and changes nothing" do
    assert_no_difference("Pickup.count") do
      post demo_reset_url, params: { sample: "true" }
    end
    assert_response :unsupported_media_type
    assert_equal({ "error" => "JSON required" }, response.parsed_body)
  end

  test "sample must be a boolean" do
    [ "true", 1, "yes" ].each do |bad|
      assert_no_difference("Pickup.count") { post demo_reset_url, params: { sample: bad }, as: :json }
      assert_response :unprocessable_content
      assert_equal({ "sample" => [ "must be true or false" ] }, response.parsed_body, bad.inspect)
    end
  end

  test "answers 404 when DEMO_RESET_DISABLED is set" do
    ENV["DEMO_RESET_DISABLED"] = "1"
    post demo_reset_url, params: { sample: false }, as: :json
    assert_response :not_found
    assert_equal({ "error" => "Not found" }, response.parsed_body)
    assert_operator customers(:acme).pickups.count, :>, 0
  ensure
    ENV.delete("DEMO_RESET_DISABLED")
  end

  test "sample serials carry the customer id, so another customer's device can't break the reset" do
    pickups(:globex_pickup).devices.create!(serial_number: "C02FK3Q1MD6R", status: "expected")
    post demo_reset_url, params: { sample: true }, as: :json
    assert_response :success
    assert customers(:acme).devices.pluck(:serial_number).all? { |serial| serial.start_with?("A#{customers(:acme).id}-") }
  end

  test "db/seeds.rb refuses to run in production without DEMO_MODE" do
    ENV.delete("DEMO_MODE")
    as_production { assert_raises(RuntimeError) { load Rails.root.join("db/seeds.rb").to_s } }
  end

  test "db/seeds.rb in production with DEMO_MODE=1 seeds the customer only, never samples unless SAMPLE=1" do
    as_production("DEMO_MODE" => "1", "SAMPLE" => "yes") do
      assert_output(/Seeded Acme Corp: 0 pickups/) { load Rails.root.join("db/seeds.rb").to_s }
    end
    assert_equal 0, customers(:acme).pickups.count
    assert_operator customers(:globex).pickups.count, :>, 0
  end
end
