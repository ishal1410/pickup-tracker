class CreatePickups < ActiveRecord::Migration[8.1]
  def change
    create_table :pickups do |t|
      t.string :company
      t.integer :device_count
      t.date :pickup_date
      t.string :status, null: false, default: "scheduled"

      t.timestamps
    end
  end
end
