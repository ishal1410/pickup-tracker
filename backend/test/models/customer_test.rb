require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "requires a name" do
    customer = Customer.new(name: "  ")
    assert_not customer.valid?
    assert_includes customer.errors[:name], "can't be blank"
  end

  test "name is unique" do
    customer = Customer.new(name: "Acme Corp")
    assert_not customer.valid?
    assert_includes customer.errors[:name], "has already been taken"
  end
end
