# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_11_02_000003) do
  create_table "customers", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_customers_on_name", unique: true
  end

  create_table "devices", force: :cascade do |t|
    t.integer "pickup_id", null: false
    t.string "serial_number", null: false
    t.string "model"
    t.string "status", default: "expected", null: false
    t.string "sanitization_method"
    t.datetime "sanitized_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["pickup_id"], name: "index_devices_on_pickup_id"
    t.index ["serial_number"], name: "index_devices_on_serial_number", unique: true
    t.check_constraint "sanitization_method IS NULL OR sanitization_method IN ('wipe', 'destroy')", name: "devices_method_allowed"
    t.check_constraint "status IN ('expected', 'received', 'sanitized', 'resold', 'donated', 'recycled')", name: "devices_status_allowed"
    t.check_constraint "status NOT IN ('resold', 'donated') OR sanitization_method = 'wipe'", name: "devices_reuse_needs_wipe"
  end

  create_table "pickups", force: :cascade do |t|
    t.integer "estimated_device_count", null: false
    t.date "pickup_date", null: false
    t.string "status", default: "scheduled", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "customer_id", null: false
    t.index ["customer_id"], name: "index_pickups_on_customer_id"
    t.check_constraint "estimated_device_count BETWEEN 1 AND 10000", name: "pickups_estimate_range"
    t.check_constraint "status IN ('scheduled', 'collected', 'cancelled')", name: "pickups_status_allowed"
  end

  add_foreign_key "devices", "pickups"
  add_foreign_key "pickups", "customers"
end
