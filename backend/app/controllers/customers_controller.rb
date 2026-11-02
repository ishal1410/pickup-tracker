class CustomersController < ApplicationController
  # GET /customer
  def show
    render json: current_customer.slice(:id, :name)
  end
end
