class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices do |t|
      t.references :pickup, null: false, foreign_key: true
      t.string :serial_number, null: false
      t.string :model
      t.string :status, null: false, default: "expected"
      t.string :sanitization_method
      t.datetime :sanitized_at
      t.timestamps
    end
    add_index :devices, :serial_number, unique: true
    add_check_constraint :devices, "status IN ('expected', 'received', 'sanitized', 'resold', 'donated', 'recycled')", name: "devices_status_allowed"
    add_check_constraint :devices, "sanitization_method IS NULL OR sanitization_method IN ('wipe', 'destroy')", name: "devices_method_allowed"
    # The compliance rule, also in the database: only a wiped device is reused.
    add_check_constraint :devices, "status NOT IN ('resold', 'donated') OR sanitization_method = 'wipe'", name: "devices_reuse_needs_wipe"
  end
end
