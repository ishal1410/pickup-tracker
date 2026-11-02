class CustomersController < ApplicationController
  # GET /customer. "today" is the server's date (Eastern), so the browser never
  # guesses it from its own zone.
  def show
    render json: current_customer.slice(:id, :name).merge(today: Date.current)
  end
end
