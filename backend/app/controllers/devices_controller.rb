# Warehouse steps. In production these come from Revivn's warehouse tools;
# in this demo only the "Warehouse simulator (demo)" panel calls them.
class DevicesController < ApplicationController
  before_action :set_device, only: %i[receive sanitize dispose]

  # POST /pickups/:pickup_id/devices: a device the customer didn't list, found at intake.
  def create
    pickup = current_customer.pickups.find(params.expect(:pickup_id))
    device = pickup.devices.new(device_params.merge(status: "received"))

    if device.save
      render json: pickup.reload.as_json_with_devices, status: :created
    else
      render json: device.errors, status: :unprocessable_content
    end
  end

  # POST /devices/:id/receive
  def receive
    render_result @device.receive
  end

  # POST /devices/:id/sanitize  { "sanitization_method": "wipe" | "destroy" }
  def sanitize
    render_result @device.sanitize(params[:sanitization_method])
  end

  # POST /devices/:id/dispose  { "outcome": "resold" | "donated" | "recycled" }
  def dispose
    render_result @device.dispose(params[:outcome])
  end

  private
    # Through the customer's pickups: another customer's device is a 404.
    def set_device
      @device = current_customer.devices.find(params.expect(:id))
    end

    def device_params
      params.expect(device: [ :serial_number, :model ])
    end

    def render_result(ok)
      if ok
        render json: @device.pickup.reload.as_json_with_devices
      else
        render json: @device.errors, status: :unprocessable_content
      end
    end
end
