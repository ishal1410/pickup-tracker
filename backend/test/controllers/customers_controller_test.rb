require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  test "shows the demo customer" do
    get customer_url, as: :json
    assert_response :success
    assert_equal({ "id" => customers(:acme).id, "name" => "Acme Corp" }, response.parsed_body)
  end

  test "answers 404 JSON when the demo customer is missing" do
    customers(:acme).update!(name: "Renamed Inc")
    get customer_url, as: :json
    assert_response :not_found
    assert_equal({ "error" => "Customer not found" }, response.parsed_body)
  end
end
