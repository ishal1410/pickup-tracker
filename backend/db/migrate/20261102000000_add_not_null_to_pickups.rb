class AddNotNullToPickups < ActiveRecord::Migration[8.1]
  def change
    change_column_null :pickups, :company, false
    change_column_null :pickups, :device_count, false
    change_column_null :pickups, :pickup_date, false
  end
end
