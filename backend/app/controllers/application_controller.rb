class ApplicationController < ActionController::API
  DEMO_CUSTOMER_NAME = "Acme Corp"

  # The contract answers 400 when the "pickup" or "device" root key is missing.
  # Rails would otherwise wrap a bare JSON body under that key for us.
  wrap_parameters false

  rescue_from ActiveRecord::RecordNotFound do |exception|
    render json: { error: "#{exception.model} not found" }, status: :not_found
  end

  rescue_from ActionController::ParameterMissing do |exception|
    render json: { error: exception.message }, status: :bad_request
  end

  private
    # ponytail: no login yet. Every query starts from current_customer, so a
    # real session lookup replaces this one method and nothing else changes.
    def current_customer
      @current_customer ||= Customer.find_by!(name: DEMO_CUSTOMER_NAME)
    end
end
