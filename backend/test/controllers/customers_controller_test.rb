require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  test "shows the demo customer" do
    get customer_url, as: :json
    assert_response :success
    assert_equal({ "id" => customers(:acme).id, "name" => "Acme Corp", "today" => Date.current.iso8601 }, response.parsed_body)
  end

  test "today is the server's Eastern date, not UTC" do
    travel_to Time.utc(2026, 11, 3, 2, 0) do # 21:00 on Nov 2 in New York
      get customer_url, as: :json
      assert_equal "2026-11-02", response.parsed_body["today"]
    end
  end

  test "answers 404 JSON when the demo customer is missing" do
    customers(:acme).update!(name: "Renamed Inc")
    get customer_url, as: :json
    assert_response :not_found
    assert_equal({ "error" => "Customer not found" }, response.parsed_body)
  end
end
