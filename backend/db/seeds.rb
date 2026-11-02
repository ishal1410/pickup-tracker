# The one demo customer. A first run starts EMPTY; SAMPLE=1 also loads the
# sample pickups (app/models/demo_data.rb). Safe to re-run: it resets Acme's data.
# It deletes data, so it never runs in production.
raise "db/seeds.rb resets demo data and must not run in production" if Rails.env.production?

acme = Customer.find_or_create_by!(name: ApplicationController::DEMO_CUSTOMER_NAME)
count = DemoData.reset!(acme, sample: ENV["SAMPLE"].present?)

puts "Seeded #{acme.name}: #{count} pickups, #{acme.devices.count} devices."
