# ADR-011: chain of custody. One row per status a device enters, never edited.
class CreateDeviceEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :device_events do |t|
      t.references :device, null: false, foreign_key: true
      t.string :from_status # null when the device was created
      t.string :to_status, null: false
      t.datetime :created_at, null: false
    end
    add_check_constraint :device_events,
      "to_status IN ('expected', 'received', 'not_received', 'sanitized', 'resold', 'donated', 'recycled')",
      name: "device_events_to_status_allowed"
  end
end
