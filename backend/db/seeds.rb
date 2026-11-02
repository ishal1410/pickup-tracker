# Demo data for the one demo customer, dated relative to today so the story
# never goes stale (a collected pickup is always in the past).
# This database only ever holds demo data, so seeding rebuilds it from scratch.
Device.delete_all
Pickup.delete_all
Customer.delete_all

def step!(record, ok)
  ok || raise("Seed broke a rule on #{record.class}: #{record.errors.full_messages.to_sentence}")
end

# Pickups dated before today were booked earlier, so only they skip the
# create-time "can't be in the past" rule. Every later step goes through the
# real model methods, so the demo data obeys every rule the app enforces.
def book(customer, date:, estimate:, serials: {})
  pickup = customer.pickups.new(pickup_date: date, estimated_device_count: estimate, serial_numbers: serials.keys)
  pickup.save!(validate: date >= Date.current)
  pickup.devices.each { |device| device.update!(model: serials.fetch(device.serial_number)) }
  pickup
end

# Receive (if booked), sanitize, and optionally give one device its outcome.
def process(device, method:, on:, outcome: nil)
  step!(device, device.receive) if device.status == "expected"
  step!(device, device.sanitize(method))
  device.update_column(:sanitized_at, on.in_time_zone.change(hour: 14)) # history, not "now"
  step!(device, device.dispose(outcome)) if outcome
end

acme = Customer.create!(name: ApplicationController::DEMO_CUSTOMER_NAME)
today = Date.current

# 1. Complete: every device sanitized and given an outcome. Certificate available.
done = book(acme, date: today - 21, estimate: 6, serials: {
  "C02FK3Q1MD6R" => "MacBook Pro 14 (2021)",
  "C02FK3Q2MD6R" => "MacBook Pro 14 (2021)",
  "C02GL7X4Q05D" => "MacBook Air M1",
  "FVFHD2K1Q6L4" => "MacBook Air M2",
  "PF3KX9ZT" => "ThinkPad T14",
  "PF3KX9ZU" => "ThinkPad T14"
})
step!(done, done.collect)
d = done.devices.order(:id).to_a
process(d[0], method: "wipe", on: today - 18, outcome: "resold")
process(d[1], method: "wipe", on: today - 18, outcome: "resold")
process(d[2], method: "wipe", on: today - 18, outcome: "resold")
process(d[3], method: "wipe", on: today - 17, outcome: "donated")
process(d[4], method: "wipe", on: today - 17, outcome: "recycled")
process(d[5], method: "destroy", on: today - 17, outcome: "recycled") # drive failed the wipe

# 2. Processing: some sanitized, some still waiting, one listed serial not found
#    yet, and one device the customer didn't list.
busy = book(acme, date: today - 9, estimate: 6, serials: {
  "C02HM8Z1Q6L4" => "MacBook Pro 16 (2021)",
  "C02HM8Z2Q6L4" => "MacBook Pro 16 (2021)",
  "FVFJK3L8Q6L9" => "MacBook Air M2",
  "PF4AB12C" => "ThinkPad X1 Carbon",
  "R9WT40ABCDE" => "Galaxy Tab S8"
})
step!(busy, busy.collect)
b = busy.devices.order(:id).to_a
process(b[0], method: "wipe", on: today - 7)
process(b[1], method: "wipe", on: today - 7)
step!(b[2], b[2].receive)
step!(b[3], b[3].receive)
# b[4] stays expected: listed by the customer, not found yet.
busy.devices.create!(serial_number: "DMPXQ0LZJF8J", model: "iPad Air (5th gen)", status: "received")

# 3. Collected two days ago; nothing checked in yet, no serials were listed.
arrived = book(acme, date: today - 2, estimate: 8)
step!(arrived, arrived.collect)

# 4. Today: the live demo. Collect it in the Warehouse simulator.
book(acme, date: today, estimate: 3, serials: {
  "C02ZQ1N4MD6T" => nil, "C02ZQ1N5MD6T" => nil, "FVFZR2P7Q6L4" => nil
})

# 5. Cancelled by the customer before collection.
cancelled = book(acme, date: today + 3, estimate: 4)
step!(cancelled, cancelled.cancel)

# 6. Upcoming, no serials yet.
book(acme, date: today + 6, estimate: 25)

puts "Seeded #{acme.name}: #{Pickup.count} pickups, #{Device.count} devices."
