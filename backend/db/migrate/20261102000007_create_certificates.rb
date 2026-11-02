# ADR-010: a certificate is issued once and stored, so its number and issue
# time never change. One per pickup.
class CreateCertificates < ActiveRecord::Migration[8.1]
  def change
    create_table :certificates do |t|
      t.references :pickup, null: false, foreign_key: true, index: { unique: true }
      t.string :number, null: false, index: { unique: true }
      t.datetime :issued_at, null: false
    end
  end
end
