class PickupsController < ApplicationController
  before_action :set_pickup, only: %i[show cancel collect certificate]

  # GET /pickups: newest pickup date first, so upcoming pickups are never cut off.
  def index
    # ponytail: newest 200, no pagination. Add page params when a customer has more.
    pickups = current_customer.pickups.order(pickup_date: :desc, id: :desc).limit(200)
    render json: Pickup.with_device_counts(pickups)
  end

  # GET /pickups/:id
  def show
    render json: @pickup.as_json_with_devices
  end

  # POST /pickups
  def create
    pickup = current_customer.pickups.new(create_params)

    if pickup.save
      render json: pickup.as_json_with_devices, status: :created
    else
      render json: pickup.errors, status: :unprocessable_content
    end
  end

  # POST /pickups/:id/cancel: the customer's only change after booking.
  def cancel
    render_result @pickup.cancel
  end

  # POST /pickups/:id/collect: called by the warehouse simulator (demo).
  def collect
    render_result @pickup.collect
  end

  # GET /pickups/:id/certificate: the customer's proof that data was destroyed.
  def certificate
    unless @pickup.certificate_available?
      return render json: { error: "Certificate is available once every device in this pickup is sanitized" }, status: :conflict
    end

    render json: @pickup.certificate
  end

  private
    # Scoped to the customer: another customer's pickup is a 404.
    def set_pickup
      @pickup = current_customer.pickups.find(params.expect(:id))
    end

    # No :status here. Every pickup starts scheduled.
    def create_params
      params.expect(pickup: [ :pickup_date, :estimated_device_count, serial_numbers: [] ])
    end

    # Every action answers with the whole pickup, so the client swaps one
    # object and sees the new progress, counts and device rows.
    def render_result(ok)
      if ok
        render json: @pickup.reload.as_json_with_devices
      else
        render json: @pickup.errors, status: :unprocessable_content
      end
    end
end
