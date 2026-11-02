# The tenant. A customer only ever sees its own pickups and devices.
class Customer < ApplicationRecord
  has_many :pickups
  has_many :devices, through: :pickups

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }
end
