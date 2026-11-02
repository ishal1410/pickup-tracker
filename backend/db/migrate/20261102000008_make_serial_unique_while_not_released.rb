# B6: a not_received device no longer holds its serial, so a cancelled or
# missing serial can be booked again. Every other device keeps it unique.
class MakeSerialUniqueWhileNotReleased < ActiveRecord::Migration[8.1]
  def change
    remove_index :devices, :serial_number, unique: true
    add_index :devices, :serial_number, unique: true, where: "status != 'not_received'"
  end
end
