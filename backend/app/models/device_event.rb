# One status a device entered, and when (ADR-011). Written only by
# ForwardOnly#move_to and when a device is created; never changed afterwards.
class DeviceEvent < ApplicationRecord
  belongs_to :device

  def readonly?
    persisted?
  end
end
