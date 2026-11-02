class ReshapePickupsForV2 < ActiveRecord::Migration[8.1]
  def up
    # ponytail: dev/test data only. Old rows have no customer, and db:seed rebuilds the demo.
    execute "DELETE FROM pickups"
    remove_column :pickups, :company
    rename_column :pickups, :device_count, :estimated_device_count
    add_reference :pickups, :customer, null: false, foreign_key: true
    add_check_constraint :pickups, "status IN ('scheduled', 'collected', 'cancelled')", name: "pickups_status_allowed"
    add_check_constraint :pickups, "estimated_device_count BETWEEN 1 AND 10000", name: "pickups_estimate_range"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
