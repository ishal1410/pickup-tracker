class DemoController < ApplicationController
  # ADR-008: dev/demo only. Off in production unless DEMO_MODE=1 (the hosted demo),
  # and always off where DEMO_RESET_DISABLED is set.
  def self.enabled?
    (ENV["DEMO_MODE"] == "1" || !Rails.env.production?) && ENV["DEMO_RESET_DISABLED"].blank?
  end

  before_action do
    unless DemoController.enabled?
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
