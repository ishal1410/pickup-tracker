# Demo data for one customer, dated relative to today so the story never goes
# stale (a collected pickup is always in the past). Used by db/seeds.rb and
# POST /demo/reset. Deleting is the one exception to "nothing is deleted"
# (ADR-008), so it only ever touches the given customer's rows.
module DemoData
  module_function

  # Empties the customer's pickups, devices, history and certificates, then optionally rebuilds the
  # 6 sample pickups / 15 devices. All or nothing.
  def reset!(customer, sample:)
    Customer.transaction do
      devices = Device.where(pickup_id: customer.pickups.select(:id))
      DeviceEvent.where(device_id: devices.select(:id)).delete_all
      devices.delete_all
      Certificate.where(pickup_id: customer.pickups.select(:id)).delete_all
      Pickup.where(customer: customer).delete_all # association delete_all would nullify
      build_sample(customer) if sample
    end
    customer.pickups.count
  end

  def build_sample(acme)
    today = Date.current
    # Serials carry the customer id ("A6-C02..."), so a real device another
    # customer holds can never collide with the sample.
    sn = ->(serial) { "A#{acme.id}-#{serial}" }

    # 1. Complete: every device sanitized and given an outcome. Certificate available.
    done = book(acme, date: today - 21, estimate: 6, serials: {
      sn.("C02FK3Q1MD6R") => "MacBook Pro 14 (2021)",
      sn.("C02FK3Q2MD6R") => "MacBook Pro 14 (2021)",
      sn.("C02GL7X4Q05D") => "MacBook Air M1",
      sn.("FVFHD2K1Q6L4") => "MacBook Air M2",
      sn.("PF3KX9ZT") => "ThinkPad T14",
      sn.("PF3KX9ZU") => "ThinkPad T14"
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
      sn.("C02HM8Z1Q6L4") => "MacBook Pro 16 (2021)",
      sn.("C02HM8Z2Q6L4") => "MacBook Pro 16 (2021)",
      sn.("FVFJK3L8Q6L9") => "MacBook Air M2",
      sn.("PF4AB12C") => "ThinkPad X1 Carbon",
      sn.("R9WT40ABCDE") => "Galaxy Tab S8"
    })
    step!(busy, busy.collect)
    b = busy.devices.order(:id).to_a
    process(b[0], method: "wipe", on: today - 7)
    process(b[1], method: "wipe", on: today - 7)
    step!(b[2], b[2].receive(at: received_at(busy)))
    step!(b[3], b[3].receive(at: received_at(busy)))
    # b[4] stays expected: listed by the customer, not found yet.
    busy.devices.create!(serial_number: sn.("DMPXQ0LZJF8J"), model: "iPad Air (5th gen)", status: "received",
      created_at: received_at(busy))

    # 3. Collected two days ago; nothing checked in yet, no serials were listed.
    arrived = book(acme, date: today - 2, estimate: 8)
    step!(arrived, arrived.collect)

    # 4. Today: the live demo. Collect it in the Warehouse simulator.
    book(acme, date: today, estimate: 3, serials: {
      sn.("C02ZQ1N4MD6T") => nil, sn.("C02ZQ1N5MD6T") => nil, sn.("FVFZR2P7Q6L4") => nil
    })

    # 5. Cancelled by the customer before collection.
    cancelled = book(acme, date: today + 3, estimate: 4)
    step!(cancelled, cancelled.cancel)

    # 6. Upcoming, no serials yet.
    book(acme, date: today + 6, estimate: 25)
  end

  def step!(record, ok)
    ok || raise("Demo data broke a rule on #{record.class}: #{record.errors.full_messages.to_sentence}")
  end

  # Pickups dated before today were booked earlier, so only they skip the
  # create-time "can't be in the past" rule. Every later step goes through the
  # real model methods, so the demo data obeys every rule the app enforces.
  def book(customer, date:, estimate:, serials: {})
    # Booked a week ahead (devices listed then), so every history starts in the past.
    booked_at = [ (date - 7).in_time_zone.change(hour: 10), Time.current ].min
    pickup = customer.pickups.new(pickup_date: date, estimated_device_count: estimate, serial_numbers: serials.keys,
      created_at: booked_at)
    pickup.save!(validate: date >= Date.current)
    pickup.devices.each { |device| device.update!(model: serials.fetch(device.serial_number)) }
    pickup
  end

  # Checked in at the warehouse late on the collection day.
  def received_at(pickup)
    pickup.pickup_date.in_time_zone.change(hour: 17)
  end

  # Receive (if booked), sanitize, and optionally give one device its outcome,
  # each backdated so the history reads in order: booked, received, sanitized, outcome.
  def process(device, method:, on:, outcome: nil)
    step!(device, device.receive(at: received_at(device.pickup))) if device.status == "expected"
    step!(device, device.sanitize(method, at: on.in_time_zone.change(hour: 14)))
    step!(device, device.dispose(outcome, at: on.in_time_zone.change(hour: 16))) if outcome
  end
end
