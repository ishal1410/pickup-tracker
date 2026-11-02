class DemoController < ApplicationController
  # ADR-008: dev/demo only. Off in production, and off anywhere DEMO_RESET_DISABLED is set.
  before_action do
    if Rails.env.production? || ENV["DEMO_RESET_DISABLED"].present?
      render json: { error: "Not found" }, status: :not_found
    end
  end

  # POST /demo/reset  {"sample": true|false}
  # JSON only: a plain HTML form (or another site posting one) can't trigger the delete.
  def reset
    return render json: { error: "JSON required" }, status: :unsupported_media_type unless request.media_type == "application/json"

    sample = params[:sample]
    unless [ true, false, nil ].include?(sample)
      return render json: { sample: [ "must be true or false" ] }, status: :unprocessable_content
    end

    count = DemoData.reset!(current_customer, sample: sample == true)
    render json: { customer: current_customer.slice(:id, :name), pickups_count: count }
  end
end
