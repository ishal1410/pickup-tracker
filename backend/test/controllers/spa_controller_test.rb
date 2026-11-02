require "test_helper"

class SpaControllerTest < ActionDispatch::IntegrationTest
  INDEX = Rails.public_path.join("index.html")

  # The built React app lives in public/ only after a production build, so make a stand-in.
  setup do
    @created = !INDEX.exist?
    INDEX.write("<!doctype html><div id=\"root\"></div>") if @created
  end

  teardown { INDEX.delete if @created }

  test "root and deep links get the React index.html" do
    [ "/", "/some/deep/link" ].each do |path|
      get path
      assert_response :success, path
      assert_equal "text/html", response.media_type, path
      assert_includes response.body, %(id="root"), path
    end
  end

  test "API paths are not shadowed" do
    get "/customer", as: :json
    assert_response :success
    assert_equal "Acme Corp", response.parsed_body["name"]

    get "/pickups/1/nope"
    assert_response :not_found
    refute_includes response.body, %(id="root")
  end

  test "a missing file is a 404, not the app" do
    get "/missing.png"
    assert_response :not_found
  end
end
