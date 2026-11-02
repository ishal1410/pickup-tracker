# Pickup Tracker v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the v1 ops-style pickup list into Acme Corp's read-only customer view: per-device lifecycle with a sanitize step, derived pickup progress, a certificate of data destruction, and a labelled warehouse simulator for the demo.

**Architecture:** Rails 8.1 API (`backend/`) with three tables (customers, pickups, devices). Status rules live in the models as a `TRANSITIONS` map shared through one concern; controllers expose action endpoints (`POST /pickups/:id/collect`, `POST /devices/:id/sanitize`, ...) instead of a free status PATCH, and every action returns the whole pickup. React 19 (`frontend/`) renders the customer view from those responses, and a separate "Warehouse simulator (demo)" panel calls the warehouse endpoints.

**Tech Stack:** Ruby 3.4, Rails 8.1 API-only, SQLite, Minitest. React 19, Vite 6, plain `fetch`, Node's built-in `node --test`.

**Source of truth:** `docs/API-v2.md` is the contract. `docs/PRD-v2.md` is the scope. If code and contract disagree, the code is wrong. Neither builder edits `docs/`.

## Global Constraints

- No new gems and no new npm packages. `Gemfile`, `Gemfile.lock`, `package.json` and `package-lock.json` stay unchanged.
- No auth. The only identity is `current_customer` (the seeded customer named "Acme Corp").
- Every line must be explainable in an interview: no metaprogramming beyond `self.class::TRANSITIONS`, no state-machine library, no serializer library.
- Scope is about 1 day. Do not build anything on the PRD cut list (address/contact, edit/reschedule, data_bearing/kind, PDF gem, audit log, pagination, filters, serial search, CSV, frontend test framework).
- Today is 2026-11-01. Server time zone is `Eastern Time (US & Canada)`. Tests and seeds use `Date.current` offsets, never hard-coded dates.
- Backend commands run in Git Bash from `C:\Users\vp141\pickup-tracker\backend` after `export PATH=/c/Ruby34-x64/bin:$PATH`. Use `ruby bin/rails ...`.
- Frontend commands run in Git Bash from `C:\Users\vp141\pickup-tracker\frontend`.
- The project is not a git repository (checked 2026-11-01). Each "Commit" step runs only if `git rev-parse --is-inside-work-tree` prints `true`; otherwise skip it.
- Track BACKEND owns `backend/**` only. Track FRONTEND owns `frontend/**` only. Track DOCS owns `README.md` and runs after both. The two build tracks run in parallel and never touch each other's files.

## File map

| File | Track | Responsibility |
|---|---|---|
| `backend/config/application.rb` | B1 | Time zone |
| `backend/db/migrate/20261102000001_create_customers.rb` | B1 | customers table |
| `backend/db/migrate/20261102000002_reshape_pickups_for_v2.rb` | B2 | pickups: customer_id, estimated_device_count, status values |
| `backend/db/migrate/20261102000003_create_devices.rb` | B3 | devices table + compliance check constraints |
| `backend/app/models/customer.rb` | B1 | Tenant |
| `backend/app/models/concerns/forward_only.rb` | B2 | `move_to` + transition validation, shared by Pickup and Device |
| `backend/app/models/pickup.rb` | B2, B3, B4 | Pickup rules, serials at booking, progress, JSON shapes |
| `backend/app/models/device.rb` | B3 | Device rules and JSON shape |
| `backend/app/controllers/application_controller.rb` | B1 | `current_customer`, 404 and 400 JSON |
| `backend/app/controllers/customers_controller.rb` | B1 | `GET /customer` |
| `backend/app/controllers/pickups_controller.rb` | B5, B6, B7 | list, detail, book, cancel, collect, certificate |
| `backend/app/controllers/devices_controller.rb` | B6 | add at intake, receive, sanitize, dispose |
| `backend/config/routes.rb` | B1, B5, B6, B7 | Routes |
| `backend/db/seeds.rb` | B8 | Demo data |
| `backend/test/fixtures/{customers,pickups,devices}.yml` | B1, B2, B3 | Fixtures with relative dates |
| `backend/test/models/*.rb`, `backend/test/controllers/*.rb` | all B | Tests |
| `frontend/vite.config.js` | F1 | Proxy `/customer`, `/pickups`, `/devices` |
| `frontend/src/lib.js` + `lib.test.js` | F1 | api(), labels, pure helpers and their tests |
| `frontend/src/index.css` | F2 | Tones, layout, simulator look, print styles |
| `frontend/src/App.jsx` | F3, F5 | Loading, list, summary, selection, action runner |
| `frontend/src/PickupDetail.jsx` | F3 | Read-only detail with progress and device table |
| `frontend/src/BookingForm.jsx` | F4 | Booking form |
| `frontend/src/WarehousePanel.jsx` | F5 | Warehouse simulator (demo) |
| `frontend/src/Certificate.jsx` | F6 | Printable certificate |
| `README.md` | D1 | Rewrite |

---

# Track BACKEND (owns `backend/**`)

Run order: B1 → B8. Each task leaves `ruby bin/rails test` green except where a step says a test must fail.

### Task B1: Customer, `current_customer`, time zone, `GET /customer`

**Files:**
- Modify: `backend/config/application.rb:36`
- Create: `backend/db/migrate/20261102000001_create_customers.rb`
- Create: `backend/app/models/customer.rb`
- Modify: `backend/app/controllers/application_controller.rb` (whole file)
- Create: `backend/app/controllers/customers_controller.rb`
- Modify: `backend/config/routes.rb`
- Create: `backend/test/fixtures/customers.yml`, `backend/test/models/customer_test.rb`, `backend/test/controllers/customers_controller_test.rb`

**Interfaces:**
- Produces: `Customer` (`name`), `ApplicationController::DEMO_CUSTOMER_NAME = "Acme Corp"`, private `current_customer` in every controller, fixtures `customers(:acme)` and `customers(:globex)`, 404 `{ "error": "<Model> not found" }`, 400 `{ "error": "<message>" }` for a missing root key.

- [ ] **Step 1: Write the failing tests**

`backend/test/fixtures/customers.yml`:
```yaml
acme:
  name: Acme Corp

globex:
  name: Globex
```

`backend/test/models/customer_test.rb`:
```ruby
require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "requires a name" do
    customer = Customer.new(name: "  ")
    assert_not customer.valid?
    assert_includes customer.errors[:name], "can't be blank"
  end

  test "name is unique" do
    customer = Customer.new(name: "Acme Corp")
    assert_not customer.valid?
    assert_includes customer.errors[:name], "has already been taken"
  end
end
```

`backend/test/controllers/customers_controller_test.rb`:
```ruby
require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  test "shows the demo customer" do
    get customer_url, as: :json
    assert_response :success
    assert_equal({ "id" => customers(:acme).id, "name" => "Acme Corp" }, response.parsed_body)
  end

  test "answers 404 JSON when the demo customer is missing" do
    customers(:acme).update!(name: "Renamed Inc")
    get customer_url, as: :json
    assert_response :not_found
    assert_equal({ "error" => "Customer not found" }, response.parsed_body)
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `ruby bin/rails test test/models/customer_test.rb test/controllers/customers_controller_test.rb`
Expected: errors such as `NameError: uninitialized constant Customer` / `customers` table missing.

- [ ] **Step 3: Implement**

`backend/config/application.rb`: replace the commented line `# config.time_zone = "Central Time (US & Canada)"` with:
```ruby
    config.time_zone = "Eastern Time (US & Canada)"
```

`backend/db/migrate/20261102000001_create_customers.rb`:
```ruby
class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :name, null: false
      t.timestamps
    end
    add_index :customers, :name, unique: true
  end
end
```

`backend/app/models/customer.rb`:
```ruby
# The tenant. A customer only ever sees its own pickups and devices.
class Customer < ApplicationRecord
  has_many :pickups
  has_many :devices, through: :pickups

  normalizes :name, with: ->(name) { name.strip }

  validates :name, presence: true, uniqueness: true, length: { maximum: 100 }
end
```

`backend/app/controllers/application_controller.rb`:
```ruby
class ApplicationController < ActionController::API
  DEMO_CUSTOMER_NAME = "Acme Corp"

  rescue_from ActiveRecord::RecordNotFound do |exception|
    render json: { error: "#{exception.model} not found" }, status: :not_found
  end

  rescue_from ActionController::ParameterMissing do |exception|
    render json: { error: exception.message }, status: :bad_request
  end

  private
    # ponytail: no login yet. Every query starts from current_customer, so a
    # real session lookup replaces this one method and nothing else changes.
    def current_customer
      @current_customer ||= Customer.find_by!(name: DEMO_CUSTOMER_NAME)
    end
end
```

`backend/app/controllers/customers_controller.rb`:
```ruby
class CustomersController < ApplicationController
  # GET /customer
  def show
    render json: current_customer.slice(:id, :name)
  end
end
```

`backend/config/routes.rb`: add `resource :customer, only: :show` as the first line inside the `draw` block (keep `resources :pickups` and the health route for now).

Run: `ruby bin/rails db:migrate`
Expected: `CreateCustomers: migrated`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `ruby bin/rails test`
Expected: all runs pass, 0 failures, 0 errors (the 27 v1 tests still pass; the customers fixture doesn't affect them).

- [ ] **Step 5: Commit**

```bash
git add backend && git commit -m "feat(backend): add Customer and current_customer"
```

### Task B2: Reshape pickups and the pickup rules

**Files:**
- Create: `backend/db/migrate/20261102000002_reshape_pickups_for_v2.rb`
- Create: `backend/app/models/concerns/forward_only.rb`
- Modify: `backend/app/models/pickup.rb` (whole file)
- Modify: `backend/test/fixtures/pickups.yml` (whole file)
- Modify: `backend/test/models/pickup_test.rb` (whole file)
- Delete: `backend/test/controllers/pickups_controller_test.rb` (v1 behaviour; replaced in B5 and B6)

**Interfaces:**
- Consumes: `customers(:acme)`, `customers(:globex)`.
- Produces: `ForwardOnly` concern (private `move_to(new_status, **attrs) -> Boolean`, transition validation reading `self.class::TRANSITIONS`). `Pickup::STATUSES`, `Pickup::TRANSITIONS`, `Pickup#collect -> Boolean`, `Pickup#cancel -> Boolean`, `Pickup#collected? -> Boolean`. Fixtures `pickups(:today)` (scheduled, today), `pickups(:upcoming)` (scheduled, today+6), `pickups(:collected)` (collected, today-7), `pickups(:globex_pickup)` (Globex, scheduled, today+2).

- [ ] **Step 1: Write the failing tests**

`backend/test/fixtures/pickups.yml`:
```yaml
today:
  customer: acme
  estimated_device_count: 3
  pickup_date: <%= Date.current %>
  status: scheduled

upcoming:
  customer: acme
  estimated_device_count: 20
  pickup_date: <%= Date.current + 6 %>
  status: scheduled

collected:
  customer: acme
  estimated_device_count: 5
  pickup_date: <%= Date.current - 7 %>
  status: collected

globex_pickup:
  customer: globex
  estimated_device_count: 4
  pickup_date: <%= Date.current + 2 %>
  status: scheduled
```

`backend/test/models/pickup_test.rb`:
```ruby
require "test_helper"

class PickupTest < ActiveSupport::TestCase
  def new_pickup(**attrs)
    Pickup.new({ customer: customers(:acme), estimated_device_count: 3, pickup_date: Date.current }.merge(attrs))
  end

  test "fixtures are valid" do
    %i[today upcoming collected globex_pickup].each { |name| assert pickups(name).valid?, name }
  end

  test "a new pickup starts scheduled" do
    assert_equal "scheduled", new_pickup.status
    assert new_pickup.valid?
  end

  test "status can't be set on create" do
    pickup = new_pickup(status: "collected")
    assert_not pickup.valid?
    assert_includes pickup.errors[:status], "must be scheduled for a new pickup"
  end

  test "estimate must be a whole number from 1 to 10,000" do
    [ 0, 10_001, 2.5, nil ].each do |bad|
      assert_not new_pickup(estimated_device_count: bad).valid?, bad.inspect
    end
    assert new_pickup(estimated_device_count: 10_000).valid?
  end

  test "requires a pickup date" do
    pickup = new_pickup(pickup_date: nil)
    assert_not pickup.valid?
    assert_includes pickup.errors[:pickup_date], "can't be blank"
  end

  test "rejects a past date on create" do
    pickup = new_pickup(pickup_date: Date.current - 1)
    assert_not pickup.valid?
    assert_includes pickup.errors[:pickup_date], "can't be in the past"
  end

  test "rejects an unknown status" do
    pickup = pickups(:today)
    pickup.status = "lost"
    assert_not pickup.valid?
  end

  test "collect moves a scheduled pickup dated today to collected" do
    pickup = pickups(:today)
    assert pickup.collect
    assert_equal "collected", pickup.reload.status
  end

  test "can't collect before the pickup date" do
    pickup = pickups(:upcoming)
    assert_not pickup.collect
    assert_includes pickup.errors[:pickup_date], "is in the future, so the pickup can't be collected yet"
    assert_equal "scheduled", pickup.reload.status
  end

  test "cancel works only while scheduled" do
    assert pickups(:upcoming).cancel
    collected = pickups(:collected)
    assert_not collected.cancel
    assert_includes collected.errors[:status], "can't go from collected to cancelled"
  end

  test "cancelling twice is rejected" do
    pickup = pickups(:upcoming)
    assert pickup.cancel
    assert_not pickup.cancel
    assert_includes pickup.errors[:status], "can't go from cancelled to cancelled"
  end

  test "status can't move backward through a direct update" do
    pickup = pickups(:collected)
    assert_not pickup.update(status: "scheduled")
    assert_includes pickup.errors[:status], "can't go from collected to scheduled"
  end

  test "database rejects an unknown status even when validations are skipped" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Pickup.insert_all([ { customer_id: customers(:acme).id, estimated_device_count: 1, pickup_date: Date.current,
                            status: "lost", created_at: Time.current, updated_at: Time.current } ])
    end
  end
end
```

Delete `backend/test/controllers/pickups_controller_test.rb`.

- [ ] **Step 2: Run to verify it fails**

Run: `ruby bin/rails test test/models/pickup_test.rb`
Expected: errors loading fixtures (`table "pickups" has no column named "customer_id"`).

- [ ] **Step 3: Implement**

`backend/db/migrate/20261102000002_reshape_pickups_for_v2.rb`:
```ruby
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
```

`backend/app/models/concerns/forward_only.rb`:
```ruby
# Shared by Pickup and Device: status only moves along the model's TRANSITIONS
# map, one step at a time. Anything not in the map is refused.
module ForwardOnly
  extend ActiveSupport::Concern

  included do
    # Guards every write, including console or seed updates.
    validate :follows_transitions, on: :update
  end

  private
    # Guards the action methods. Unlike the validation, it also refuses a
    # repeat (sanitized -> sanitized), so a second sanitize can't swap the method.
    def move_to(new_status, **attrs)
      unless self.class::TRANSITIONS.fetch(status, []).include?(new_status)
        errors.add(:status, "can't go from #{status} to #{new_status}")
        return false
      end
      update(status: new_status, **attrs)
    end

    def follows_transitions
      return unless status_changed?
      unless self.class::TRANSITIONS.fetch(status_was, []).include?(status)
        errors.add(:status, "can't go from #{status_was} to #{status}")
      end
    end
end
```

`backend/app/models/pickup.rb`:
```ruby
class Pickup < ApplicationRecord
  include ForwardOnly

  STATUSES = %w[scheduled collected cancelled].freeze
  # Only these moves are stored. "processing" and "complete" are derived
  # from the devices, so the pickup can never disagree with its devices.
  TRANSITIONS = { "scheduled" => %w[collected cancelled] }.freeze

  belongs_to :customer

  validates :estimated_device_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :pickup_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :starts_scheduled, on: :create
  validate :pickup_date_not_in_past, on: :create
  validate :not_collected_before_pickup_date

  def collect
    move_to("collected")
  end

  # The customer's only change after booking. Nothing is ever deleted.
  def cancel
    move_to("cancelled")
  end

  def collected?
    status == "collected"
  end

  private
    def starts_scheduled
      errors.add(:status, "must be scheduled for a new pickup") unless status == "scheduled"
    end

    def pickup_date_not_in_past
      errors.add(:pickup_date, "can't be in the past") if pickup_date && pickup_date < Date.current
    end

    def not_collected_before_pickup_date
      return unless status_changed? && status == "collected" && pickup_date
      errors.add(:pickup_date, "is in the future, so the pickup can't be collected yet") if pickup_date > Date.current
    end
end
```

Run: `ruby bin/rails db:migrate`
Expected: `ReshapePickupsForV2: migrated`. Then `grep -c check_constraint db/schema.rb` prints `2`.

- [ ] **Step 4: Run the tests**

Run: `ruby bin/rails test`
Expected: 0 failures, 0 errors. (The v1 controller test file is gone; `pickups_controller.rb` still has v1 code until B5, which no test exercises.)

- [ ] **Step 5: Commit**

```bash
git add backend && git commit -m "feat(backend): pickups belong to a customer; scheduled/collected/cancelled"
```

### Task B3: Device table and the device rules

**Files:**
- Create: `backend/db/migrate/20261102000003_create_devices.rb`
- Create: `backend/app/models/device.rb`
- Modify: `backend/app/models/pickup.rb` (add `has_many :devices` under `belongs_to :customer`)
- Create: `backend/test/fixtures/devices.yml`, `backend/test/models/device_test.rb`

**Interfaces:**
- Consumes: `ForwardOnly`, `Pickup#collected?`, pickup fixtures.
- Produces: `Device::STATUSES`, `Device::OUTCOMES`, `Device::SANITIZATION_METHODS`, `Device::TRANSITIONS`, `Device#receive -> Boolean`, `Device#sanitize(method) -> Boolean`, `Device#dispose(outcome) -> Boolean`, `Device#as_json -> Hash` (string keys: id, pickup_id, serial_number, model, status, sanitization_method, sanitized_at, created_at, updated_at). Fixtures: `devices(:expected_one)` on `today`; `received_one`, `wiped_one`, `destroyed_one`, `resold_one` on `collected`; `globex_device` on `globex_pickup`.

- [ ] **Step 1: Write the failing tests**

`backend/test/fixtures/devices.yml`:
```yaml
expected_one:
  pickup: today
  serial_number: C02EXP0001
  status: expected

received_one:
  pickup: collected
  serial_number: C02REC0001
  model: MacBook Pro 14
  status: received

wiped_one:
  pickup: collected
  serial_number: C02WIP0001
  status: sanitized
  sanitization_method: wipe
  sanitized_at: <%= 1.day.ago.utc.to_fs(:db) %>

destroyed_one:
  pickup: collected
  serial_number: C02DES0001
  status: sanitized
  sanitization_method: destroy
  sanitized_at: <%= 1.day.ago.utc.to_fs(:db) %>

resold_one:
  pickup: collected
  serial_number: C02RES0001
  status: resold
  sanitization_method: wipe
  sanitized_at: <%= 2.days.ago.utc.to_fs(:db) %>

globex_device:
  pickup: globex_pickup
  serial_number: GLX0000001
  status: expected
```

`backend/test/models/device_test.rb`:
```ruby
require "test_helper"

class DeviceTest < ActiveSupport::TestCase
  test "fixtures are valid" do
    Device.all.each { |device| assert device.valid?, device.serial_number }
  end

  test "serial is trimmed and uppercased" do
    assert_equal "C02ABC", Device.new(serial_number: "  c02abc ").serial_number
  end

  test "serial is required, unique and at most 50 characters" do
    device = pickups(:collected).devices.new(status: "received", serial_number: "")
    assert_not device.valid?
    device.serial_number = "c02rec0001"
    assert_not device.valid?
    assert_includes device.errors[:serial_number], "has already been taken"
    device.serial_number = "X" * 51
    assert_not device.valid?
  end

  test "a new device starts expected or received" do
    device = pickups(:collected).devices.new(serial_number: "NEW1", status: "sanitized", sanitization_method: "wipe")
    assert_not device.valid?
    assert_includes device.errors[:status], "must be expected or received for a new device"
  end

  test "a received device needs a collected pickup" do
    device = pickups(:today).devices.new(serial_number: "NEW2", status: "received")
    assert_not device.valid?
    assert_includes device.errors[:pickup], "must be collected first"
  end

  test "receive is refused while the pickup is still scheduled" do
    device = devices(:expected_one)
    assert_not device.receive
    assert_includes device.errors[:pickup], "must be collected first"
  end

  test "receive works once the pickup is collected" do
    assert pickups(:today).collect
    device = Device.find(devices(:expected_one).id)
    assert device.receive
    assert_equal "received", device.reload.status
  end

  test "sanitize records the method and the time" do
    device = devices(:received_one)
    assert device.sanitize("wipe")
    device.reload
    assert_equal %w[sanitized wipe], [ device.status, device.sanitization_method ]
    assert_not_nil device.sanitized_at
  end

  test "sanitize rejects an unknown method" do
    device = devices(:received_one)
    assert_not device.sanitize("melt")
    assert_includes device.errors[:sanitization_method], "is not included in the list"
  end

  test "sanitizing twice is refused, so the method can't be swapped" do
    device = devices(:destroyed_one)
    assert_not device.sanitize("wipe")
    assert_includes device.errors[:status], "can't go from sanitized to sanitized"
    assert_equal "destroy", device.reload.sanitization_method
  end

  test "compliance: no outcome before sanitize" do
    device = devices(:received_one)
    assert_not device.dispose("resold")
    assert_includes device.errors[:status], "can't go from received to resold"
    assert_equal "received", device.reload.status
  end

  test "a wiped device can be donated" do
    assert devices(:wiped_one).dispose("donated")
    assert_equal "donated", devices(:wiped_one).reload.status
  end

  test "a destroyed device can only be recycled" do
    device = devices(:destroyed_one)
    assert_not device.dispose("resold")
    assert_includes device.errors[:status], "can only be recycled after the drive is destroyed"
    assert_not Device.find(device.id).dispose("donated")
    assert Device.find(device.id).dispose("recycled")
  end

  test "outcomes are final" do
    device = devices(:resold_one)
    assert_not device.dispose("donated")
    assert_includes device.errors[:status], "can't go from resold to donated"
  end

  test "dispose rejects a value that is not an outcome" do
    device = devices(:wiped_one)
    assert_not device.dispose("sanitized")
    assert_includes device.errors[:status], "must be one of: resold, donated, recycled"
  end

  test "no backward moves through a direct update" do
    device = devices(:wiped_one)
    assert_not device.update(status: "received")
    assert_includes device.errors[:status], "can't go from sanitized to received"
  end

  test "as_json exposes exactly the contract fields" do
    assert_equal %w[created_at id model pickup_id sanitization_method sanitized_at serial_number status updated_at],
      devices(:received_one).as_json.keys.sort
  end

  test "database refuses a reused device whose drive was destroyed, even without validations" do
    assert_raises(ActiveRecord::StatementInvalid) do
      Device.insert_all([ { pickup_id: pickups(:collected).id, serial_number: "RAW1", status: "resold",
                            sanitization_method: "destroy", sanitized_at: Time.current,
                            created_at: Time.current, updated_at: Time.current } ])
    end
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `ruby bin/rails test test/models/device_test.rb`
Expected: errors (`devices` table / `Device` constant missing).

- [ ] **Step 3: Implement**

`backend/db/migrate/20261102000003_create_devices.rb`:
```ruby
class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    create_table :devices do |t|
      t.references :pickup, null: false, foreign_key: true
      t.string :serial_number, null: false
      t.string :model
      t.string :status, null: false, default: "expected"
      t.string :sanitization_method
      t.datetime :sanitized_at
      t.timestamps
    end
    add_index :devices, :serial_number, unique: true
    add_check_constraint :devices, "status IN ('expected', 'received', 'sanitized', 'resold', 'donated', 'recycled')", name: "devices_status_allowed"
    add_check_constraint :devices, "sanitization_method IS NULL OR sanitization_method IN ('wipe', 'destroy')", name: "devices_method_allowed"
    # The compliance rule, also in the database: only a wiped device is reused.
    add_check_constraint :devices, "status NOT IN ('resold', 'donated') OR sanitization_method = 'wipe'", name: "devices_reuse_needs_wipe"
  end
end
```

`backend/app/models/device.rb`:
```ruby
# One physical device, identified by its serial number. This is the unit that
# gets sanitized, gets an outcome, and appears on the certificate.
# ponytail: every device is treated as data-bearing. Add a data_bearing flag
# when monitors and peripherals come in.
class Device < ApplicationRecord
  include ForwardOnly

  STATUSES = %w[expected received sanitized resold donated recycled].freeze
  OUTCOMES = %w[resold donated recycled].freeze
  SANITIZATION_METHODS = %w[wipe destroy].freeze
  # No path skips "sanitized", so no device reaches an outcome with its data
  # intact. Outcomes have no exits.
  TRANSITIONS = {
    "expected" => %w[received],
    "received" => %w[sanitized],
    "sanitized" => OUTCOMES
  }.freeze

  belongs_to :pickup

  normalizes :serial_number, with: ->(serial) { serial.strip.upcase }

  validates :serial_number, presence: true, length: { maximum: 50 }, uniqueness: true
  validates :model, length: { maximum: 100 }
  validates :status, inclusion: { in: STATUSES }
  validates :sanitization_method, inclusion: { in: SANITIZATION_METHODS }, unless: :before_sanitize?
  validate :starts_expected_or_received, on: :create
  validate :pickup_collected_for_warehouse_steps
  validate :destroyed_device_only_recycled

  def receive
    move_to("received")
  end

  def sanitize(method)
    move_to("sanitized", sanitization_method: method, sanitized_at: Time.current)
  end

  def dispose(outcome)
    unless OUTCOMES.include?(outcome)
      errors.add(:status, "must be one of: #{OUTCOMES.join(', ')}")
      return false
    end
    move_to(outcome)
  end

  def as_json(_options = nil)
    {
      "id" => id,
      "pickup_id" => pickup_id,
      "serial_number" => serial_number,
      "model" => model,
      "status" => status,
      "sanitization_method" => sanitization_method,
      "sanitized_at" => sanitized_at,
      "created_at" => created_at,
      "updated_at" => updated_at
    }
  end

  private
    def before_sanitize?
      %w[expected received].include?(status)
    end

    def starts_expected_or_received
      errors.add(:status, "must be expected or received for a new device") unless before_sanitize?
    end

    # Only Revivn touches a device after it leaves the customer, and only
    # once the pickup is collected.
    def pickup_collected_for_warehouse_steps
      return if status == "expected" || pickup.nil?
      errors.add(:pickup, "must be collected first") unless pickup.collected?
    end

    def destroyed_device_only_recycled
      if sanitization_method == "destroy" && %w[resold donated].include?(status)
        errors.add(:status, "can only be recycled after the drive is destroyed")
      end
    end
end
```

`backend/app/models/pickup.rb`: add `has_many :devices` on the line after `belongs_to :customer`.

Run: `ruby bin/rails db:migrate`
Expected: `CreateDevices: migrated`. Then `grep -c check_constraint db/schema.rb` prints `5`.

- [ ] **Step 4: Run the tests**

Run: `ruby bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add backend && git commit -m "feat(backend): devices with sanitize-before-outcome rules"
```

### Task B4: Serials at booking, derived progress, JSON shapes

**Files:**
- Modify: `backend/app/models/pickup.rb` (whole file below)
- Create: `backend/test/models/pickup_progress_test.rb`

**Interfaces:**
- Consumes: `Device::STATUSES`, `Device::OUTCOMES`, `Device#as_json`.
- Produces: `Pickup#serial_numbers=(Array<String> | nil)`, `Pickup#progress -> "scheduled" | "collected" | "processing" | "complete" | "cancelled"`, `Pickup#certificate_available? -> Boolean`, `Pickup#device_counts -> Hash` (string keys: the 6 device statuses + `"total"`), `Pickup#as_json -> Hash` (pickup summary, API-v2 3.1), `Pickup#as_json_with_devices -> Hash` (pickup detail, API-v2 3.2).

- [ ] **Step 1: Write the failing test**

`backend/test/models/pickup_progress_test.rb`:
```ruby
require "test_helper"

class PickupProgressTest < ActiveSupport::TestCase
  def book(serials)
    Pickup.create(customer: customers(:acme), estimated_device_count: 3, pickup_date: Date.current, serial_numbers: serials)
  end

  test "serials at booking become expected devices, trimmed and uppercased" do
    pickup = book([ " c02new1 ", "", "C02NEW2" ])
    assert pickup.persisted?
    assert_equal %w[C02NEW1 C02NEW2], pickup.devices.order(:id).pluck(:serial_number)
    assert_equal %w[expected expected], pickup.devices.pluck(:status)
  end

  test "serials are optional" do
    assert_equal 0, book(nil).devices.count
  end

  test "a serial listed twice blocks the booking" do
    assert_no_difference("Pickup.count") do
      pickup = book(%w[C02DUP c02dup])
      assert_includes pickup.errors[:serial_numbers], "C02DUP is listed more than once"
    end
  end

  test "an already registered serial blocks the booking" do
    pickup = book(%w[C02EXP0001])
    assert_includes pickup.errors[:serial_numbers], "C02EXP0001 is already registered"
  end

  test "a serial longer than 50 characters blocks the booking" do
    pickup = book([ "A" * 51 ])
    assert_includes pickup.errors[:serial_numbers], "#{"A" * 51} is longer than 50 characters"
  end

  test "progress mirrors the stored status before collection" do
    assert_equal "scheduled", pickups(:today).progress
    pickups(:upcoming).cancel
    assert_equal "cancelled", pickups(:upcoming).progress
  end

  test "a collected pickup with only expected devices is 'collected'" do
    pickup = pickups(:today)
    pickup.collect
    assert_equal "collected", pickup.reload.progress
  end

  test "a collected pickup with devices in flight is 'processing'" do
    assert_equal "processing", pickups(:collected).progress
  end

  test "a collected pickup is 'complete' once every device has an outcome" do
    devices(:received_one).sanitize("wipe")
    Device.find(devices(:received_one).id).dispose("donated")
    devices(:wiped_one).dispose("resold")
    devices(:destroyed_one).dispose("recycled")
    assert_equal "complete", pickups(:collected).reload.progress
  end

  test "device_counts has every status plus total" do
    assert_equal({ "expected" => 0, "received" => 1, "sanitized" => 2, "resold" => 1, "donated" => 0, "recycled" => 0, "total" => 4 },
      pickups(:collected).device_counts)
  end

  test "certificate is available only when every device is sanitized" do
    assert_not pickups(:collected).certificate_available?
    devices(:received_one).sanitize("wipe")
    assert pickups(:collected).reload.certificate_available?
  end

  test "certificate is not available for a pickup with no devices" do
    assert_not pickups(:upcoming).certificate_available?
  end

  test "as_json is the pickup summary from the contract" do
    json = pickups(:collected).as_json
    assert_equal %w[certificate_available created_at device_counts estimated_device_count id pickup_date progress status updated_at],
      json.keys.sort
    assert_equal "processing", json["progress"]
  end

  test "as_json_with_devices adds the devices in id order" do
    json = pickups(:collected).as_json_with_devices
    assert_equal pickups(:collected).devices.order(:id).pluck(:id), json["devices"].map { |d| d["id"] }
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `ruby bin/rails test test/models/pickup_progress_test.rb`
Expected: errors such as `ActiveModel::UnknownAttributeError: unknown attribute 'serial_numbers'` and `NoMethodError: undefined method 'progress'`.

- [ ] **Step 3: Implement**

`backend/app/models/pickup.rb` (whole file):
```ruby
class Pickup < ApplicationRecord
  include ForwardOnly

  STATUSES = %w[scheduled collected cancelled].freeze
  # Only these moves are stored. "processing" and "complete" are derived
  # from the devices (see #progress), so they can never disagree.
  TRANSITIONS = { "scheduled" => %w[collected cancelled] }.freeze

  belongs_to :customer
  has_many :devices

  attr_reader :serial_numbers

  validates :estimated_device_count, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 10_000 }
  validates :pickup_date, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate :starts_scheduled, on: :create
  validate :pickup_date_not_in_past, on: :create
  validate :serial_numbers_valid, on: :create
  validate :not_collected_before_pickup_date

  after_create :create_expected_devices

  def collect
    move_to("collected")
  end

  # The customer's only change after booking. Nothing is ever deleted.
  def cancel
    move_to("cancelled")
  end

  def collected?
    status == "collected"
  end

  # Optional at booking: trimmed, uppercased, blank lines dropped.
  def serial_numbers=(list)
    @serial_numbers = Array(list).map { |serial| serial.to_s.strip.upcase }.reject(&:empty?)
  end

  def progress
    return status unless collected?

    list = devices.to_a
    return "complete" if list.any? && list.all? { |device| Device::OUTCOMES.include?(device.status) }
    return "processing" if list.any? { |device| device.status != "expected" }
    "collected"
  end

  def certificate_available?
    list = devices.to_a
    list.any? && list.all? { |device| device.sanitized_at.present? }
  end

  def device_counts
    list = devices.to_a
    Device::STATUSES.index_with { |status| list.count { |device| device.status == status } }.merge("total" => list.size)
  end

  # API-v2 3.1: the pickup summary.
  def as_json(_options = nil)
    {
      "id" => id,
      "pickup_date" => pickup_date,
      "estimated_device_count" => estimated_device_count,
      "status" => status,
      "progress" => progress,
      "device_counts" => device_counts,
      "certificate_available" => certificate_available?,
      "created_at" => created_at,
      "updated_at" => updated_at
    }
  end

  # API-v2 3.2: the summary plus devices, in booking then intake order.
  def as_json_with_devices
    as_json.merge("devices" => devices.sort_by(&:id).map(&:as_json))
  end

  private
    def starts_scheduled
      errors.add(:status, "must be scheduled for a new pickup") unless status == "scheduled"
    end

    def pickup_date_not_in_past
      errors.add(:pickup_date, "can't be in the past") if pickup_date && pickup_date < Date.current
    end

    def not_collected_before_pickup_date
      return unless status_changed? && status == "collected" && pickup_date
      errors.add(:pickup_date, "is in the future, so the pickup can't be collected yet") if pickup_date > Date.current
    end

    # ponytail: serials are unique across all customers because a physical
    # device exists once. The message reveals that a serial exists elsewhere;
    # scope it per customer if that matters.
    def serial_numbers_valid
      serials = Array(serial_numbers)
      serials.tally.each { |serial, count| errors.add(:serial_numbers, "#{serial} is listed more than once") if count > 1 }
      serials.select { |serial| serial.length > 50 }.each { |serial| errors.add(:serial_numbers, "#{serial} is longer than 50 characters") }
      Device.where(serial_number: serials).pluck(:serial_number).each { |serial| errors.add(:serial_numbers, "#{serial} is already registered") }
    end

    def create_expected_devices
      Array(serial_numbers).each { |serial| devices.create!(serial_number: serial, status: "expected") }
    end
end
```

- [ ] **Step 4: Run the tests**

Run: `ruby bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add backend && git commit -m "feat(backend): serials at booking, derived progress, JSON shapes"
```

### Task B5: Customer-scoped list, detail and booking endpoints

**Files:**
- Modify: `backend/app/controllers/pickups_controller.rb` (whole file)
- Modify: `backend/config/routes.rb` (whole file)
- Create: `backend/test/controllers/pickups_controller_test.rb`

**Interfaces:**
- Consumes: `current_customer`, `Pickup#as_json`, `Pickup#as_json_with_devices`.
- Produces: `GET /pickups`, `GET /pickups/:id`, `POST /pickups` exactly as API-v2 4.2 to 4.4. `PATCH`/`DELETE` routes are removed.

- [ ] **Step 1: Write the failing test**

`backend/test/controllers/pickups_controller_test.rb`:
```ruby
require "test_helper"

class PickupsControllerTest < ActionDispatch::IntegrationTest
  SUMMARY_KEYS = %w[certificate_available created_at device_counts estimated_device_count id pickup_date progress status updated_at].freeze

  test "index lists only the current customer's pickups" do
    get pickups_url, as: :json
    assert_response :success
    ids = response.parsed_body.map { |p| p["id"] }
    assert_includes ids, pickups(:today).id
    assert_not_includes ids, pickups(:globex_pickup).id
  end

  test "index puts the newest pickup date first" do
    get pickups_url, as: :json
    dates = response.parsed_body.map { |p| p["pickup_date"] }
    assert_equal dates.sort.reverse, dates
    assert_equal pickups(:upcoming).id, response.parsed_body.first["id"]
  end

  test "index uses the summary shape, without devices" do
    get pickups_url, as: :json
    assert_equal SUMMARY_KEYS, response.parsed_body.first.keys.sort
  end

  test "index keeps the 200 most recent pickups, so upcoming ones are never cut off" do
    now = Time.current
    old = Array.new(205) do |i|
      { customer_id: customers(:acme).id, estimated_device_count: 1, pickup_date: Date.current - 400 - i,
        status: "collected", created_at: now, updated_at: now }
    end
    Pickup.insert_all(old)

    get pickups_url, as: :json
    assert_equal 200, response.parsed_body.size
    assert_equal pickups(:upcoming).id, response.parsed_body.first["id"]
  end

  test "show returns the detail shape with devices" do
    get pickup_url(pickups(:collected)), as: :json
    assert_response :success
    assert_equal (SUMMARY_KEYS + [ "devices" ]).sort, response.parsed_body.keys.sort
    assert_equal 4, response.parsed_body["devices"].size
    assert_equal "processing", response.parsed_body["progress"]
  end

  test "show hides another customer's pickup behind a 404" do
    get pickup_url(pickups(:globex_pickup)), as: :json
    assert_response :not_found
    assert_equal({ "error" => "Pickup not found" }, response.parsed_body)
  end

  test "create books a scheduled pickup with expected devices" do
    assert_difference({ "Pickup.count" => 1, "Device.count" => 2 }) do
      post pickups_url, params: { pickup: { pickup_date: Date.current.to_s, estimated_device_count: "2",
                                            serial_numbers: [ "c02a1", "C02A2" ] } }, as: :json
    end
    assert_response :created
    body = response.parsed_body
    assert_equal %w[scheduled scheduled], body.values_at("status", "progress")
    assert_equal %w[C02A1 C02A2], body["devices"].map { |d| d["serial_number"] }
    assert_equal customers(:acme).id, Pickup.find(body["id"]).customer_id
  end

  test "create ignores a status sent by the client" do
    post pickups_url, params: { pickup: { pickup_date: Date.current.to_s, estimated_device_count: 1, status: "collected" } }, as: :json
    assert_response :created
    assert_equal "scheduled", response.parsed_body["status"]
  end

  test "create with missing fields returns 422 keyed by field" do
    post pickups_url, params: { pickup: { pickup_date: "", estimated_device_count: "" } }, as: :json
    assert_response :unprocessable_content
    assert_equal %w[estimated_device_count pickup_date], response.parsed_body.keys.sort
  end

  test "create rejects a past date" do
    post pickups_url, params: { pickup: { pickup_date: (Date.current - 1).to_s, estimated_device_count: 1 } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup_date" => [ "can't be in the past" ] }, response.parsed_body)
  end

  test "create rejects a serial that is already registered" do
    post pickups_url, params: { pickup: { pickup_date: Date.current.to_s, estimated_device_count: 1,
                                          serial_numbers: [ "C02EXP0001" ] } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "serial_numbers" => [ "C02EXP0001 is already registered" ] }, response.parsed_body)
  end

  test "create without a pickup key returns 400 JSON" do
    post pickups_url, params: {}, as: :json
    assert_response :bad_request
    assert response.parsed_body["error"].present?
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `ruby bin/rails test test/controllers/pickups_controller_test.rb`
Expected: failures and errors (v1 controller still uses `Pickup.ordered_by_date` and `:company`).

- [ ] **Step 3: Implement**

`backend/config/routes.rb`:
```ruby
Rails.application.routes.draw do
  resource :customer, only: :show
  resources :pickups, only: %i[index show create]

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
```

`backend/app/controllers/pickups_controller.rb`:
```ruby
class PickupsController < ApplicationController
  before_action :set_pickup, only: %i[show]

  # GET /pickups: newest pickup date first, so upcoming pickups are never cut off.
  def index
    # ponytail: newest 200, no pagination. Add page params when a customer has more.
    pickups = current_customer.pickups.includes(:devices).order(pickup_date: :desc, id: :desc).limit(200)
    render json: pickups
  end

  # GET /pickups/:id
  def show
    render json: @pickup.as_json_with_devices
  end

  # POST /pickups
  def create
    pickup = current_customer.pickups.new(create_params)

    if pickup.save
      render json: pickup.as_json_with_devices, status: :created
    else
      render json: pickup.errors, status: :unprocessable_content
    end
  end

  private
    # Scoped to the customer: another customer's pickup is a 404.
    def set_pickup
      @pickup = current_customer.pickups.find(params.expect(:id))
    end

    # No :status here. Every pickup starts scheduled.
    def create_params
      params.expect(pickup: [ :pickup_date, :estimated_device_count, serial_numbers: [] ])
    end
end
```

- [ ] **Step 4: Run the tests**

Run: `ruby bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add backend && git commit -m "feat(backend): customer-scoped pickups API, newest first"
```

### Task B6: Action endpoints (cancel, collect, add device, receive, sanitize, dispose)

**Files:**
- Modify: `backend/app/controllers/pickups_controller.rb` (add `cancel`, `collect`, `render_result`; widen `before_action`)
- Create: `backend/app/controllers/devices_controller.rb`
- Modify: `backend/config/routes.rb` (whole file)
- Create: `backend/test/controllers/pickup_actions_test.rb`, `backend/test/controllers/devices_controller_test.rb`

**Interfaces:**
- Consumes: `Pickup#cancel`, `Pickup#collect`, `Device#receive`, `Device#sanitize`, `Device#dispose`, `Customer#devices`.
- Produces: API-v2 4.5 to 4.8. URL helpers `cancel_pickup_url`, `collect_pickup_url`, `pickup_devices_url`, `receive_device_url`, `sanitize_device_url`, `dispose_device_url`.

- [ ] **Step 1: Write the failing tests**

`backend/test/controllers/pickup_actions_test.rb`:
```ruby
require "test_helper"

class PickupActionsTest < ActionDispatch::IntegrationTest
  test "cancel a scheduled pickup" do
    post cancel_pickup_url(pickups(:upcoming)), as: :json
    assert_response :success
    assert_equal %w[cancelled cancelled], response.parsed_body.values_at("status", "progress")
  end

  test "cancel a collected pickup is refused with the reason" do
    post cancel_pickup_url(pickups(:collected)), as: :json
    assert_response :unprocessable_content
    assert_equal({ "status" => [ "can't go from collected to cancelled" ] }, response.parsed_body)
  end

  test "collect a pickup dated today" do
    post collect_pickup_url(pickups(:today)), as: :json
    assert_response :success
    assert_equal %w[collected collected], response.parsed_body.values_at("status", "progress")
    assert_equal 1, response.parsed_body["devices"].size
  end

  test "collect a future pickup is refused" do
    post collect_pickup_url(pickups(:upcoming)), as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup_date" => [ "is in the future, so the pickup can't be collected yet" ] }, response.parsed_body)
  end

  test "actions on another customer's pickup answer 404" do
    post cancel_pickup_url(pickups(:globex_pickup)), as: :json
    assert_response :not_found
    assert_equal({ "error" => "Pickup not found" }, response.parsed_body)
  end

  test "pickups can no longer be edited or deleted" do
    patch pickup_url(pickups(:today)), params: { pickup: { status: "collected" } }, as: :json
    assert_response :not_found
    delete pickup_url(pickups(:today)), as: :json
    assert_response :not_found
    assert_equal "scheduled", pickups(:today).reload.status
  end
end
```

`backend/test/controllers/devices_controller_test.rb`:
```ruby
require "test_helper"

class DevicesControllerTest < ActionDispatch::IntegrationTest
  def device_json(id)
    response.parsed_body["devices"].find { |d| d["id"] == id }
  end

  test "warehouse adds an unlisted device to a collected pickup" do
    assert_difference("Device.count", 1) do
      post pickup_devices_url(pickups(:collected)), params: { device: { serial_number: " dmpx1 ", model: "iPad Air" } }, as: :json
    end
    assert_response :created
    added = response.parsed_body["devices"].last
    assert_equal [ "DMPX1", "iPad Air", "received" ], added.values_at("serial_number", "model", "status")
  end

  test "adding a device to a scheduled pickup is refused" do
    post pickup_devices_url(pickups(:today)), params: { device: { serial_number: "NEW9" } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup" => [ "must be collected first" ] }, response.parsed_body)
  end

  test "adding a duplicate serial is refused" do
    post pickup_devices_url(pickups(:collected)), params: { device: { serial_number: "C02REC0001" } }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "serial_number" => [ "has already been taken" ] }, response.parsed_body)
  end

  test "receive an expected device once the pickup is collected" do
    pickups(:today).collect
    post receive_device_url(devices(:expected_one)), as: :json
    assert_response :success
    assert_equal "received", device_json(devices(:expected_one).id)["status"]
    assert_equal "processing", response.parsed_body["progress"]
  end

  test "receive while the pickup is scheduled is refused" do
    post receive_device_url(devices(:expected_one)), as: :json
    assert_response :unprocessable_content
    assert_equal({ "pickup" => [ "must be collected first" ] }, response.parsed_body)
  end

  test "sanitize by wipe" do
    post sanitize_device_url(devices(:received_one)), params: { sanitization_method: "wipe" }, as: :json
    assert_response :success
    device = device_json(devices(:received_one).id)
    assert_equal %w[sanitized wipe], device.values_at("status", "sanitization_method")
    assert device["sanitized_at"].present?
  end

  test "sanitize with an unknown method is refused" do
    post sanitize_device_url(devices(:received_one)), params: { sanitization_method: "melt" }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "sanitization_method" => [ "is not included in the list" ] }, response.parsed_body)
  end

  test "dispose before sanitize is refused" do
    post dispose_device_url(devices(:received_one)), params: { outcome: "resold" }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "status" => [ "can't go from received to resold" ] }, response.parsed_body)
  end

  test "a destroyed device can't be resold but can be recycled" do
    post dispose_device_url(devices(:destroyed_one)), params: { outcome: "resold" }, as: :json
    assert_response :unprocessable_content
    assert_equal({ "status" => [ "can only be recycled after the drive is destroyed" ] }, response.parsed_body)

    post dispose_device_url(devices(:destroyed_one)), params: { outcome: "recycled" }, as: :json
    assert_response :success
  end

  test "the last outcome completes the pickup" do
    post sanitize_device_url(devices(:received_one)), params: { sanitization_method: "wipe" }, as: :json
    post dispose_device_url(devices(:received_one)), params: { outcome: "donated" }, as: :json
    post dispose_device_url(devices(:wiped_one)), params: { outcome: "resold" }, as: :json
    post dispose_device_url(devices(:destroyed_one)), params: { outcome: "recycled" }, as: :json
    assert_response :success
    assert_equal "complete", response.parsed_body["progress"]
    assert response.parsed_body["certificate_available"]
  end

  test "another customer's device answers 404" do
    post receive_device_url(devices(:globex_device)), as: :json
    assert_response :not_found
    assert_equal({ "error" => "Device not found" }, response.parsed_body)
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `ruby bin/rails test test/controllers/pickup_actions_test.rb test/controllers/devices_controller_test.rb`
Expected: `NoMethodError: undefined method 'cancel_pickup_url'` and similar. (The "can no longer be edited or deleted" test already passes after B5; that's fine.)

- [ ] **Step 3: Implement**

`backend/config/routes.rb`:
```ruby
Rails.application.routes.draw do
  resource :customer, only: :show

  resources :pickups, only: %i[index show create] do
    member do
      post :cancel
      post :collect
    end
    resources :devices, only: :create
  end

  resources :devices, only: [] do
    member do
      post :receive
      post :sanitize
      post :dispose
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
```

`backend/app/controllers/pickups_controller.rb`: change the first line of the class body to
```ruby
  before_action :set_pickup, only: %i[show cancel collect]
```
add these actions after `create`:
```ruby
  # POST /pickups/:id/cancel: the customer's only change after booking.
  def cancel
    render_result @pickup.cancel
  end

  # POST /pickups/:id/collect: called by the warehouse simulator (demo).
  def collect
    render_result @pickup.collect
  end
```
and add this private method after `create_params`:
```ruby
    # Every action answers with the whole pickup, so the client swaps one
    # object and sees the new progress, counts and device rows.
    def render_result(ok)
      if ok
        render json: @pickup.reload.as_json_with_devices
      else
        render json: @pickup.errors, status: :unprocessable_content
      end
    end
```

`backend/app/controllers/devices_controller.rb`:
```ruby
# Warehouse steps. In production these come from Revivn's warehouse tools;
# in this demo only the "Warehouse simulator (demo)" panel calls them.
class DevicesController < ApplicationController
  before_action :set_device, only: %i[receive sanitize dispose]

  # POST /pickups/:pickup_id/devices: a device the customer didn't list, found at intake.
  def create
    pickup = current_customer.pickups.find(params.expect(:pickup_id))
    device = pickup.devices.new(device_params.merge(status: "received"))

    if device.save
      render json: pickup.reload.as_json_with_devices, status: :created
    else
      render json: device.errors, status: :unprocessable_content
    end
  end

  # POST /devices/:id/receive
  def receive
    render_result @device.receive
  end

  # POST /devices/:id/sanitize  { "sanitization_method": "wipe" | "destroy" }
  def sanitize
    render_result @device.sanitize(params[:sanitization_method])
  end

  # POST /devices/:id/dispose  { "outcome": "resold" | "donated" | "recycled" }
  def dispose
    render_result @device.dispose(params[:outcome])
  end

  private
    # Through the customer's pickups: another customer's device is a 404.
    def set_device
      @device = current_customer.devices.find(params.expect(:id))
    end

    def device_params
      params.expect(device: [ :serial_number, :model ])
    end

    def render_result(ok)
      if ok
        render json: @device.pickup.reload.as_json_with_devices
      else
        render json: @device.errors, status: :unprocessable_content
      end
    end
end
```

- [ ] **Step 4: Run the tests**

Run: `ruby bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add backend && git commit -m "feat(backend): action endpoints replace status PATCH and DELETE"
```

### Task B7: Certificate endpoint (409 until every device is sanitized)

**Files:**
- Modify: `backend/app/controllers/pickups_controller.rb` (add `certificate`; add it to `before_action`)
- Modify: `backend/config/routes.rb` (add `get :certificate` inside the pickups `member` block)
- Create: `backend/test/controllers/certificates_test.rb`

**Interfaces:**
- Consumes: `Pickup#certificate_available?`, `Device#as_json`.
- Produces: `GET /pickups/:id/certificate` exactly as API-v2 4.9, helper `certificate_pickup_url`.

- [ ] **Step 1: Write the failing test**

`backend/test/controllers/certificates_test.rb`:
```ruby
require "test_helper"

class CertificatesTest < ActionDispatch::IntegrationTest
  test "409 until every device is sanitized" do
    get certificate_pickup_url(pickups(:collected)), as: :json
    assert_response :conflict
    assert_equal({ "error" => "Certificate is available once every device in this pickup is sanitized" }, response.parsed_body)
  end

  test "409 for a pickup with no devices" do
    get certificate_pickup_url(pickups(:upcoming)), as: :json
    assert_response :conflict
  end

  test "lists every device once all are sanitized" do
    devices(:received_one).sanitize("wipe")

    get certificate_pickup_url(pickups(:collected)), as: :json
    assert_response :success
    body = response.parsed_body
    assert_equal %w[customer_name devices issued_at pickup_date pickup_id standard], body.keys.sort
    assert_equal [ "Acme Corp", "NIST SP 800-88", pickups(:collected).id ], body.values_at("customer_name", "standard", "pickup_id")
    assert_equal %w[C02DES0001 C02REC0001 C02RES0001 C02WIP0001], body["devices"].map { |d| d["serial_number"] }
    assert_equal %w[model sanitization_method sanitized_at serial_number status], body["devices"].first.keys.sort
  end

  test "another customer's certificate answers 404" do
    get certificate_pickup_url(pickups(:globex_pickup)), as: :json
    assert_response :not_found
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `ruby bin/rails test test/controllers/certificates_test.rb`
Expected: `NoMethodError: undefined method 'certificate_pickup_url'`.

- [ ] **Step 3: Implement**

`backend/config/routes.rb`: the pickups member block becomes
```ruby
    member do
      post :cancel
      post :collect
      get :certificate
    end
```

`backend/app/controllers/pickups_controller.rb`: change the `before_action` to `only: %i[show cancel collect certificate]` and add after `collect`:
```ruby
  # GET /pickups/:id/certificate: the customer's proof that data was destroyed.
  def certificate
    unless @pickup.certificate_available?
      return render json: { error: "Certificate is available once every device in this pickup is sanitized" }, status: :conflict
    end

    render json: {
      pickup_id: @pickup.id,
      customer_name: current_customer.name,
      pickup_date: @pickup.pickup_date,
      standard: "NIST SP 800-88",
      issued_at: Time.current,
      devices: @pickup.devices.sort_by(&:serial_number).map do |device|
        device.as_json.slice("serial_number", "model", "sanitization_method", "sanitized_at", "status")
      end
    }
  end
```

- [ ] **Step 4: Run the tests**

Run: `ruby bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add backend && git commit -m "feat(backend): certificate endpoint, 409 until all devices sanitized"
```

### Task B8: Realistic seeds dated from today

**Files:**
- Modify: `backend/db/seeds.rb` (whole file)

**Interfaces:**
- Consumes: every model method above.
- Produces: the demo data table in API-v2 section 5.

- [ ] **Step 1: Run the check to see it fail**

Run: `ruby bin/rails db:seed`
Expected: fails with `unknown attribute 'company' for Pickup` (v1 seeds).

- [ ] **Step 2: Implement**

`backend/db/seeds.rb`:
```ruby
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
```

- [ ] **Step 3: Run the seed twice and check the result**

Run: `ruby bin/rails db:seed && ruby bin/rails db:seed`
Expected (twice): `Seeded Acme Corp: 6 pickups, 15 devices.`

Run:
```bash
ruby bin/rails runner 'Pickup.order(:pickup_date).each { |p| puts [p.pickup_date, p.status, p.progress, p.certificate_available?, p.devices.size].join(" ") }'
```
Expected on 2026-11-01:
```
2026-10-11 collected complete true 6
2026-10-23 collected processing false 6
2026-10-30 collected collected false 0
2026-11-01 scheduled scheduled false 3
2026-11-04 cancelled cancelled false 0
2026-11-07 scheduled scheduled false 0
```

- [ ] **Step 4: Run the full suite once more**

Run: `ruby bin/rails test`
Expected: 0 failures, 0 errors.

- [ ] **Step 5: Commit**

```bash
git add backend && git commit -m "feat(backend): seeds replay real rules, dated from today"
```

---

# Track FRONTEND (owns `frontend/**`)

Runs in parallel with Track BACKEND. Code only against `docs/API-v2.md`. Browser checks against the real API happen in D1, after both tracks finish. Each task's own check is `node --test`, `npm run lint`, `npm run build` and greps.

### Task F1: Proxy, `api()`, labels and pure helpers (test-first with `node --test`)

**Files:**
- Modify: `frontend/vite.config.js`
- Create: `frontend/src/lib.js`
- Create: `frontend/src/lib.test.js`

**Interfaces:**
- Produces (all named exports of `src/lib.js`):
  - `PROGRESS_LABELS`, `DEVICE_LABELS` (key order = display order: expected, received, sanitized, resold, donated, recycled), `METHOD_LABELS`
  - `api(path, method = 'GET', body) -> Promise<json>`; throws `Error` with `.status`; on 422 also `.fields` (`{ field: [messages] }`); on other errors `.message` is the server's `error` string when present
  - `errorMessages(fields) -> string[]`, `errorText(err) -> string`
  - `parseSerials(text) -> string[]`, `todayLocal(now?) -> 'YYYY-MM-DD'`
  - `formatDate('YYYY-MM-DD') -> 'Nov 3, 2026'`, `formatDateTime(iso) -> 'Oct 14, 2026, 2:00 PM'`
  - `upsertPickup(list, pickup) -> list` (replace or insert, sorted by `pickup_date` desc then `id` desc)

- [ ] **Step 1: Write the failing test**

`frontend/src/lib.test.js`:
```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { api, errorMessages, errorText, formatDate, parseSerials, todayLocal, upsertPickup } from './lib.js'

test('errorMessages turns Rails keys into sentences', () => {
  assert.deepEqual(
    errorMessages({ status: ["can't go from received to resold"], pickup_date: ["can't be in the past"] }),
    ["Status can't go from received to resold", "Pickup date can't be in the past"],
  )
})

test('errorText prefers field messages, then the plain message', () => {
  const fieldErr = Object.assign(new Error('x'), { fields: { pickup: ['must be collected first'] } })
  assert.equal(errorText(fieldErr), 'Pickup must be collected first')
  assert.equal(errorText(new Error('Pickup not found')), 'Pickup not found')
})

test('parseSerials trims and drops blank lines', () => {
  assert.deepEqual(parseSerials(' C02A \n\n  c02b\n   '), ['C02A', 'c02b'])
  assert.deepEqual(parseSerials(''), [])
})

test('todayLocal uses local date parts, not UTC', () => {
  assert.equal(todayLocal(new Date(2026, 10, 1, 23, 59)), '2026-11-01')
})

test('formatDate never shifts the day', () => {
  assert.equal(formatDate('2026-11-03'), 'Nov 3, 2026')
})

test('upsertPickup replaces by id and keeps newest date first', () => {
  const list = [{ id: 1, pickup_date: '2026-11-07' }, { id: 2, pickup_date: '2026-10-11' }]
  const replaced = upsertPickup(list, { id: 2, pickup_date: '2026-10-11', progress: 'complete' })
  assert.equal(replaced.find(p => p.id === 2).progress, 'complete')
  const inserted = upsertPickup(list, { id: 3, pickup_date: '2026-11-01' })
  assert.deepEqual(inserted.map(p => p.id), [1, 3, 2])
})

test('api returns parsed JSON on success', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ id: 1 }), { status: 200 })
  assert.deepEqual(await api('/customer'), { id: 1 })
})

test('api puts 422 field errors on err.fields', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ status: ['bad'] }), { status: 422 })
  await assert.rejects(api('/x', 'POST', {}), err => err.status === 422 && err.fields.status[0] === 'bad')
})

test('api uses the server error message on 409', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ error: 'Certificate is available once every device in this pickup is sanitized' }), { status: 409 })
  await assert.rejects(api('/pickups/1/certificate'), err => err.status === 409 && err.message.startsWith('Certificate is available'))
})

test('api survives a non-JSON error body', async () => {
  globalThis.fetch = async () => new Response('Not Found', { status: 404 })
  await assert.rejects(api('/nope'), err => err.status === 404 && err.message === 'Request failed (404)')
})
```

- [ ] **Step 2: Run to verify it fails**

Run: `node --test src/lib.test.js`
Expected: FAIL, `Cannot find module '.../src/lib.js'`.

- [ ] **Step 3: Implement**

`frontend/vite.config.js`:
```js
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// ponytail: dev proxy to Rails instead of rack-cors
const rails = 'http://localhost:3000'
export default defineConfig({
  plugins: [react()],
  server: { proxy: { '/customer': rails, '/pickups': rails, '/devices': rails } },
})
```

`frontend/src/lib.js`:
```js
// Labels for every status in docs/API-v2.md section 2. Key order is display order.
export const PROGRESS_LABELS = {
  scheduled: 'Scheduled',
  collected: 'Collected',
  processing: 'Processing',
  complete: 'Complete',
  cancelled: 'Cancelled',
}
export const DEVICE_LABELS = {
  expected: 'Expected',
  received: 'Received',
  sanitized: 'Sanitized',
  resold: 'Resold',
  donated: 'Donated',
  recycled: 'Recycled',
}
export const METHOD_LABELS = { wipe: 'Wiped', destroy: 'Drive destroyed' }

// One place for every request. A failure throws an Error with .status.
// 422 also carries .fields ({ field: [messages] }); other errors use the
// server's { error } text as the message when there is one.
export async function api(path, method = 'GET', body) {
  const res = await fetch(path, {
    method,
    headers: { 'Content-Type': 'application/json' },
    body: body && JSON.stringify(body),
  })
  const data = await res.json().catch(() => null)
  if (res.ok) return data
  const err = new Error(data?.error ?? `Request failed (${res.status})`)
  err.status = res.status
  if (res.status === 422) err.fields = data ?? {}
  throw err
}

// { pickup_date: ["can't be in the past"] } -> ["Pickup date can't be in the past"]
export function errorMessages(fields) {
  return Object.entries(fields).flatMap(([field, messages]) => {
    const name = field.replaceAll('_', ' ')
    const label = name.charAt(0).toUpperCase() + name.slice(1)
    return messages.map(message => `${label} ${message}`)
  })
}

export function errorText(err) {
  return err.fields ? errorMessages(err.fields).join('. ') : err.message
}

// Textarea -> list. The server still trims, uppercases and validates.
export function parseSerials(text) {
  return text.split('\n').map(line => line.trim()).filter(Boolean)
}

// Today in the browser's timezone. toISOString() would use UTC.
export function todayLocal(now = new Date()) {
  const pad = n => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
}

// "2026-11-03" -> "Nov 3, 2026". Built from parts so the timezone can't shift the day.
export function formatDate(isoDate) {
  const [y, m, d] = isoDate.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

export function formatDateTime(iso) {
  return new Date(iso).toLocaleString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit',
  })
}

// Insert or replace one pickup, keeping the server's order (newest date first).
export function upsertPickup(list, pickup) {
  const rest = list.filter(p => p.id !== pickup.id)
  return [...rest, pickup].sort((a, b) => b.pickup_date.localeCompare(a.pickup_date) || b.id - a.id)
}
```

- [ ] **Step 4: Run the tests and lint**

Run: `node --test src/lib.test.js && npm run lint`
Expected: `# pass 10`, `# fail 0`; lint prints no errors.

- [ ] **Step 5: Commit**

```bash
git add frontend && git commit -m "feat(frontend): api helper, labels and tested pure helpers"
```

### Task F2: Styles for v2 (tones, wrapping, 32px buttons, simulator look, print)

**Files:**
- Modify: `frontend/src/index.css`

**Interfaces:**
- Produces CSS classes used by F3 to F6: `tone-<status>` for all 11 status/progress values, `.pill`, `.segment`, `.dot`, `.btn-secondary`, `.btn-danger`, `.hint`, `.notice`, `.row-error`, `.selected`, `.serial`, `.detail-grid`, `.detail-actions`, `.step-actions`, `.devices`, `.progress`, `.simulator`, `.demo-tag`, `.add-device`, `.certificate-shell`, `.certificate`, `.cert-facts`, `.no-print`, `.date`.

- [ ] **Step 1: Run the check to see it fail**

Run: `grep -c "tone-picked_up\|\.stepper\|\.sort " src/index.css; grep -c "@media print" src/index.css`
Expected: first number greater than 0 (v1 classes present), second `0`.

- [ ] **Step 2: Edit `index.css`**

1. In the top comment, replace the second and third lines with `Cool paper background, one deep green accent, one tone per status.`
2. In `:root`, delete the comment `/* Stage colors: solid for bars/steps, tint + text for pills. */` and the four lines starting `--scheduled:`, `--picked_up:`, `--refurbished:`, `--donated:`.
3. Delete these rule groups entirely: the four `.segment.tone-*` rules, the four `.dot.tone-*` rules, the four `.pill.tone-*` rules, `.sort` and `.sort:hover`, `.company`, the desktop `.status-cell` rule and its comment, and everything from `.stepper` through `.step.reached.tone-donated::before` (including the `/* Each step is ... */` comment).
4. In `.legend`, replace `grid-template-columns: repeat(4, minmax(0, 1fr));` with `grid-template-columns: repeat(auto-fit, minmax(110px, 1fr));`. In the `max-width: 900px` media query delete the `.legend` line.
5. Change the selectors `input {`, `input:hover`, `input:focus`, `input[aria-invalid='true']` to `input, textarea {`, `input:hover, textarea:hover`, `input:focus, textarea:focus`, `input[aria-invalid='true'], textarea[aria-invalid='true']`. Change `button, input { font: inherit; color: inherit; }` to `button, input, textarea { font: inherit; color: inherit; }`.
6. In the `max-width: 640px` media query, replace `.company { grid-column: 1; }` with `.date { grid-column: 1; font-weight: 500; }` and delete the `.status-cell { ... }` line.
7. Insert this block just above the `/* ---------- Responsive ---------- */` comment:

```css
/* ---------- v2: tones, detail, simulator, certificate ---------- */

/* One tone per status. Pills use the tint, bars and dots the solid color. */
.tone-scheduled, .tone-expected { --tone: #6683b5; --tone-tint: #e5ebf5; --tone-text: #34507d; }
.tone-collected, .tone-received, .tone-processing { --tone: #c98d2e; --tone-tint: #f6ead3; --tone-text: #7f5410; }
.tone-sanitized, .tone-complete { --tone: #2e8a70; --tone-tint: #dceee7; --tone-text: #1d6551; }
.tone-resold { --tone: #1d5c4b; --tone-tint: #d3e5de; --tone-text: #164a3c; }
.tone-donated { --tone: #8c62a8; --tone-tint: #eee4f4; --tone-text: #63407c; }
.tone-recycled, .tone-cancelled { --tone: #7a837f; --tone-tint: #e8eae8; --tone-text: #464e4a; }
.segment, .dot { background: var(--tone); }
.pill { background: var(--tone-tint); color: var(--tone-text); }

/* Long names and serials with no spaces wrap instead of widening the page. */
h1, h2, td, th, dd, .serial { overflow-wrap: anywhere; }
.workspace > *, .detail-grid > * { min-width: 0; }

textarea { resize: vertical; font-family: ui-monospace, 'SF Mono', Consolas, monospace; }
.hint { color: var(--muted); font-size: 0.8667rem; margin-top: 6px; }
ul.field-error { margin: 6px 0 0; padding-left: 18px; }
.notice { margin-bottom: 16px; padding: 10px 14px; border-radius: 12px; background: #dceee7; color: #1d6551; }
.notice:empty { display: none; }
.row-error { color: var(--danger); font-size: 0.8667rem; margin-top: 6px; text-align: left; white-space: normal; }

/* Every button has visible text and is at least 32px tall (WCAG 2.2 asks for 24px). */
.btn { min-height: 32px; }
.btn-secondary { padding: 6px 14px; background: rgba(27, 36, 32, 0.06); color: var(--ink); }
.btn-secondary:hover { background: rgba(27, 36, 32, 0.12); }
.btn-secondary:disabled { opacity: 0.5; cursor: not-allowed; }
.btn-danger { color: var(--danger); }
.detail-actions .btn-primary { width: auto; margin-top: 0; }

tr.selected td { background: rgba(29, 92, 75, 0.06); }
tbody th { text-align: left; padding: 14px 12px; border-bottom: 1px solid var(--hairline); font-weight: 500; }
.serial { font-family: ui-monospace, 'SF Mono', Consolas, monospace; color: var(--ink); font-size: 0.9333rem; }

.detail-grid { display: grid; grid-template-columns: 1.4fr 1fr; gap: 24px; align-items: start; margin-top: 24px; }
.detail-actions { display: flex; flex-wrap: wrap; gap: 8px; margin-top: 16px; }
.step-actions { display: flex; flex-wrap: wrap; gap: 6px; }
.devices { margin-top: 20px; }

/* Progress: four labelled steps, filled up to the current one. */
.progress { list-style: none; display: flex; flex-wrap: wrap; gap: 6px; padding: 0; margin: 0 0 12px; }
.progress li { flex: 1 1 90px; padding-top: 8px; border-top: 4px solid rgba(27, 36, 32, 0.1); color: var(--muted); font-size: 0.8667rem; }
.progress li.done { border-top-color: var(--accent); color: var(--ink); }
.progress li[aria-current='step'] { font-weight: 600; }

/* The simulator must never look like part of the customer's screen. */
.simulator { background: repeating-linear-gradient(-45deg, #f6ead3, #f6ead3 10px, #fbf3e3 10px, #fbf3e3 20px); box-shadow: inset 0 0 0 2px #c98d2e; }
.demo-tag { display: inline-block; margin-bottom: 8px; padding: 2px 8px; border-radius: 999px; background: #7f5410; color: #fff; font-size: 0.8rem; font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em; }
.add-device { display: grid; grid-template-columns: 1fr 1fr auto; gap: 12px; align-items: end; margin: 16px 0 4px; }
.add-device .field { margin-bottom: 0; }

.certificate-shell { margin-top: 24px; }
.cert-facts { display: grid; grid-template-columns: max-content 1fr; gap: 6px 16px; margin: 0 0 20px; }
.cert-facts dt { color: var(--muted); }
.cert-facts dd { margin: 0; font-weight: 500; }

@media (max-width: 900px) {
  .detail-grid { grid-template-columns: 1fr; }
  .add-device { grid-template-columns: 1fr; }
}

@media (max-width: 640px) {
  tbody th { display: block; padding: 0; border: 0; grid-column: 1 / -1; }
  .step-actions { grid-column: 1 / -1; }
}

/* Print only the certificate. */
@media print {
  body * { visibility: hidden; }
  .certificate, .certificate * { visibility: visible; }
  .certificate { position: absolute; inset: 0; box-shadow: none; padding: 0; }
  .no-print { display: none; }
}
```

- [ ] **Step 3: Run the check again**

Run: `grep -c "tone-picked_up\|\.stepper\|\.sort " src/index.css; grep -c "@media print" src/index.css; npm run build`
Expected: `0`, `1`, and Vite prints `built in`.

- [ ] **Step 4: Commit**

```bash
git add frontend && git commit -m "style(frontend): v2 tones, wrapping, 32px buttons, print styles"
```

### Task F3: App shell: customer header, list, summary, read-only detail

**Files:**
- Modify: `frontend/src/App.jsx` (whole file; F5 adds nothing more to it)
- Create: `frontend/src/PickupDetail.jsx`
- Create (stub, finished in F4/F5/F6): `frontend/src/BookingForm.jsx`, `frontend/src/WarehousePanel.jsx`, `frontend/src/Certificate.jsx`

**Interfaces:**
- Consumes: everything from `lib.js`; API-v2 4.1, 4.2, 4.3, 4.5.
- Produces (props contracts the later tasks implement):
  - `<BookingForm disabled={bool} onBooked={(pickupDetail) => void} />`
  - `<PickupDetail pickup={pickupDetail} rowError={{key, message} | null} onCancel={() => void} onShowCertificate={() => void} />`
  - `<WarehousePanel pickup={pickupDetail} rowError={...} onAction={(action) => Promise<boolean>} />` where `action = { key, pickupId, path, body?, confirmText?, focusIds? }`
  - `<Certificate pickupId={number} onClose={() => void} />`
  - Element ids other tasks focus: `detail-heading`, `warehouse-heading`, `wh-serial`, `wh-device-<id>`, `cert-heading`.
  - `rowError.key` values: `list-<pickupId>`, `pickup-<pickupId>`, `collect`, `add-device`, `device-<deviceId>`.

- [ ] **Step 1: Run the check to see it fail**

Run: `grep -c "picked_up\|setPickups(\[\|setPickups(pickups\|deletePickup" src/App.jsx; ls src/PickupDetail.jsx`
Expected: a number greater than 0, and `No such file or directory`.

- [ ] **Step 2: Write the stubs so App compiles**

`frontend/src/BookingForm.jsx`:
```jsx
export default function BookingForm() {
  return null
}
```
`frontend/src/WarehousePanel.jsx`:
```jsx
export default function WarehousePanel() {
  return null
}
```
`frontend/src/Certificate.jsx`:
```jsx
export default function Certificate() {
  return null
}
```

- [ ] **Step 3: Write `PickupDetail.jsx`**

```jsx
import { DEVICE_LABELS, formatDate, formatDateTime, METHOD_LABELS, PROGRESS_LABELS } from './lib.js'

const STEPS = ['scheduled', 'collected', 'processing', 'complete']

// The customer's read-only view of one pickup. Their only action is Cancel,
// and only while the pickup is scheduled.
export default function PickupDetail({ pickup, rowError, onCancel, onShowCertificate }) {
  const c = pickup.device_counts
  const sanitized = c.sanitized + c.resold + c.donated + c.recycled
  const current = STEPS.indexOf(pickup.progress)

  return (
    <section className="shell" aria-labelledby="detail-heading">
      <div className="core">
        <h2 id="detail-heading" tabIndex={-1}>Pickup on {formatDate(pickup.pickup_date)}</h2>

        {pickup.progress === 'cancelled' ? (
          <p><span className="pill tone-cancelled">Cancelled</span></p>
        ) : (
          <ol className="progress" aria-label="Progress">
            {STEPS.map((step, i) => (
              <li key={step} className={i <= current ? 'done' : undefined} aria-current={i === current ? 'step' : undefined}>
                {PROGRESS_LABELS[step]}
              </li>
            ))}
          </ol>
        )}

        <p className="hint">
          Estimated {pickup.estimated_device_count} · {c.total - c.expected} checked in · {sanitized} of {c.total} sanitized
        </p>

        <div className="detail-actions">
          <button type="button" className="btn btn-secondary" disabled={!pickup.certificate_available} onClick={onShowCertificate}>
            View certificate of data destruction
          </button>
          {pickup.status === 'scheduled' && (
            <button type="button" className="btn btn-secondary btn-danger" onClick={onCancel}>Cancel pickup</button>
          )}
        </div>
        {!pickup.certificate_available && (
          <p className="hint">The certificate is ready once every device is sanitized ({sanitized} of {c.total} so far).</p>
        )}
        {rowError?.key === `pickup-${pickup.id}` && <p className="row-error" role="alert">{rowError.message}</p>}

        {pickup.devices.length === 0 ? (
          <p className="state">No devices listed yet. Revivn records each serial number when the devices arrive.</p>
        ) : (
          <table className="devices">
            <thead>
              <tr>
                <th scope="col">Serial number</th>
                <th scope="col">Model</th>
                <th scope="col">Status</th>
                <th scope="col">Data sanitized</th>
              </tr>
            </thead>
            <tbody>
              {pickup.devices.map(d => (
                <tr key={d.id}>
                  <th scope="row" className="serial">{d.serial_number}</th>
                  <td data-label="Model">{d.model || '—'}</td>
                  <td><span className={`pill tone-${d.status}`}>{DEVICE_LABELS[d.status]}</span></td>
                  <td data-label="Sanitized">
                    {d.sanitized_at ? `${METHOD_LABELS[d.sanitization_method]}, ${formatDateTime(d.sanitized_at)}` : 'Not yet'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </section>
  )
}
```

- [ ] **Step 4: Write `App.jsx`**

```jsx
import { useEffect, useState } from 'react'
import { api, DEVICE_LABELS, errorText, formatDate, PROGRESS_LABELS, upsertPickup } from './lib.js'
import BookingForm from './BookingForm.jsx'
import PickupDetail from './PickupDetail.jsx'
import WarehousePanel from './WarehousePanel.jsx'
import Certificate from './Certificate.jsx'

const DEVICE_STATUSES = Object.keys(DEVICE_LABELS)

// Focus the first of these ids that exists, after React has painted.
// ponytail: ids + requestAnimationFrame instead of a ref per row.
function focusById(...ids) {
  requestAnimationFrame(() => {
    for (const id of ids) {
      const el = document.getElementById(id)
      if (el) {
        el.focus()
        return
      }
    }
  })
}

export default function App() {
  const [customer, setCustomer] = useState(null)
  const [pickups, setPickups] = useState([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState(null)
  const [reloadKey, setReloadKey] = useState(0)
  const [selected, setSelected] = useState(null) // pickup detail, with devices
  const [certificateId, setCertificateId] = useState(null)
  const [rowError, setRowError] = useState(null) // { key, message }, shown next to the control that failed
  const [notice, setNotice] = useState('')

  useEffect(() => {
    let ignore = false
    setLoading(true)
    setLoadError(null)
    Promise.all([api('/customer'), api('/pickups')])
      .then(([me, list]) => {
        if (!ignore) {
          setCustomer(me)
          setPickups(list)
        }
      })
      .catch(() => { if (!ignore) setLoadError("Couldn't load your pickups. Please try again in a moment.") })
      .finally(() => { if (!ignore) setLoading(false) })
    return () => { ignore = true }
  }, [reloadKey])

  function forget(id) {
    setPickups(prev => prev.filter(p => p.id !== id))
    setSelected(prev => (prev?.id === id ? null : prev))
    setNotice('That pickup no longer exists.')
  }

  async function openPickup(id) {
    setRowError(null)
    setCertificateId(null)
    try {
      const detail = await api(`/pickups/${id}`)
      setSelected(detail)
      setPickups(prev => upsertPickup(prev, detail))
      focusById('detail-heading')
    } catch (err) {
      if (err.status === 404) forget(id)
      else setRowError({ key: `list-${id}`, message: errorText(err) })
    }
  }

  // After a failed action the screen may be stale (another tab changed it), so refetch.
  async function refresh(id) {
    try {
      const detail = await api(`/pickups/${id}`)
      setPickups(prev => upsertPickup(prev, detail))
      setSelected(prev => (prev?.id === id ? detail : prev))
    } catch (err) {
      if (err.status === 404) forget(id)
    }
  }

  // Every action endpoint returns the whole pickup (API-v2 section 1), so one
  // success path keeps the list row and the open panel in sync.
  async function runAction({ key, pickupId, path, body, confirmText, focusIds = [] }) {
    if (confirmText && !window.confirm(confirmText)) return false
    setRowError(null)
    try {
      const updated = await api(path, 'POST', body)
      setPickups(prev => upsertPickup(prev, updated))
      setSelected(prev => (prev?.id === updated.id ? updated : prev))
      return true
    } catch (err) {
      setRowError({ key, message: errorText(err) })
      await refresh(pickupId)
      return false
    } finally {
      focusById(...focusIds, 'detail-heading')
    }
  }

  function handleBooked(pickup) {
    setPickups(prev => upsertPickup(prev, pickup))
    setSelected(pickup)
    setCertificateId(null)
    const n = pickup.device_counts.total
    setNotice(`Pickup booked for ${formatDate(pickup.pickup_date)}${n ? ` with ${n} serial number${n === 1 ? '' : 's'}` : ''}.`)
    focusById('detail-heading')
  }

  // Totals across this customer's pickups, from data we already have.
  const totals = Object.fromEntries(
    DEVICE_STATUSES.map(s => [s, pickups.reduce((sum, p) => sum + p.device_counts[s], 0)]),
  )
  const allDevices = pickups.reduce((sum, p) => sum + p.device_counts.total, 0)
  const checkedIn = allDevices - totals.expected
  const sanitized = totals.sanitized + totals.resold + totals.donated + totals.recycled
  const activePickups = pickups.filter(p => p.status !== 'cancelled').length
  const figure = n => (loadError ? '—' : n)

  return (
    <div className="page">
      <header className="masthead">
        <div className="brand-mark" aria-hidden="true" />
        <div>
          <h1>{customer ? `${customer.name}: your pickups` : 'Your pickups'}</h1>
          <p className="lede">Book hardware pickups, follow every device through data sanitization, and download proof when it's done.</p>
        </div>
      </header>

      {loadError && (
        <div className="banner" role="alert">
          <p>{loadError}</p>
          <button type="button" className="btn btn-quiet" onClick={() => setReloadKey(k => k + 1)}>Retry</button>
        </div>
      )}
      <p className="notice" role="status">{notice}</p>

      <section className="summary" aria-label="Summary">
        <div className="totals">
          <div><p className="figure">{figure(activePickups)}</p><p className="figure-label">Pickups</p></div>
          <div><p className="figure">{figure(checkedIn)}</p><p className="figure-label">Devices checked in</p></div>
          <div><p className="figure">{figure(sanitized)}</p><p className="figure-label">Data sanitized</p></div>
        </div>
        <div className="pipeline">
          <p className="pipeline-title">Devices by status</p>
          <div className="pipeline-bar" aria-hidden="true">
            {DEVICE_STATUSES.map(s => totals[s] > 0 && (
              <span key={s} className={`segment tone-${s}`} style={{ flexGrow: totals[s] }} />
            ))}
          </div>
          <ul className="legend">
            {DEVICE_STATUSES.map(s => (
              <li key={s}>
                <span className={`dot tone-${s}`} aria-hidden="true" />
                <span className="legend-name">{DEVICE_LABELS[s]}</span>
                <span className="legend-count">{figure(totals[s])}</span>
              </li>
            ))}
          </ul>
        </div>
      </section>

      <div className="workspace">
        <BookingForm disabled={Boolean(loadError)} onBooked={handleBooked} />

        <section className="shell" aria-labelledby="pickups-heading">
          <div className="core list">
            <h2 id="pickups-heading">Your pickups</h2>

            {loading && <p className="state">Loading pickups…</p>}
            {!loading && !loadError && pickups.length === 0 && (
              <p className="state">No pickups yet. Book the first one with the form.</p>
            )}

            {!loading && pickups.length > 0 && (
              <table>
                <thead>
                  <tr>
                    <th scope="col">Pickup date</th>
                    <th scope="col">Devices</th>
                    <th scope="col">Progress</th>
                    <th scope="col"><span className="visually-hidden">Actions</span></th>
                  </tr>
                </thead>
                <tbody>
                  {pickups.map(p => {
                    const isOpen = selected?.id === p.id
                    return (
                      <tr key={p.id} className={isOpen ? 'selected' : undefined} aria-current={isOpen ? 'true' : undefined}>
                        <td className="date">{formatDate(p.pickup_date)}</td>
                        <td data-label="Devices">
                          {p.device_counts.total - p.device_counts.expected} checked in · est. {p.estimated_device_count}
                        </td>
                        <td><span className={`pill tone-${p.progress}`}>{PROGRESS_LABELS[p.progress]}</span></td>
                        <td className="actions">
                          <button type="button" className="btn btn-secondary" onClick={() => openPickup(p.id)}
                            aria-label={`View pickup on ${formatDate(p.pickup_date)}`}>
                            View
                          </button>
                          {rowError?.key === `list-${p.id}` && <p className="row-error" role="alert">{rowError.message}</p>}
                        </td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            )}
          </div>
        </section>
      </div>

      {selected && (
        <div className="detail-grid">
          <PickupDetail
            pickup={selected}
            rowError={rowError}
            onCancel={() => runAction({
              key: `pickup-${selected.id}`,
              pickupId: selected.id,
              path: `/pickups/${selected.id}/cancel`,
              confirmText: `Cancel the pickup on ${formatDate(selected.pickup_date)}? This can't be undone.`,
              focusIds: ['detail-heading'],
            })}
            onShowCertificate={() => setCertificateId(selected.id)}
          />
          <WarehousePanel pickup={selected} rowError={rowError} onAction={runAction} />
        </div>
      )}

      {certificateId && (
        <Certificate
          key={certificateId}
          pickupId={certificateId}
          onClose={() => {
            setCertificateId(null)
            focusById('detail-heading')
          }}
        />
      )}
    </div>
  )
}
```

- [ ] **Step 5: Run the checks**

Run: `grep -c "picked_up\|setPickups(\[\|setPickups(pickups\|deletePickup" src/App.jsx; npm run lint && npm run build && node --test src/lib.test.js`
Expected: `0`; lint clean; `built in`; `# fail 0`.

- [ ] **Step 6: Commit**

```bash
git add frontend && git commit -m "feat(frontend): customer list, summary and read-only pickup detail"
```

### Task F4: Booking form

**Files:**
- Modify: `frontend/src/BookingForm.jsx` (replace the stub)

**Interfaces:**
- Consumes: `api`, `errorMessages`, `parseSerials`, `todayLocal`; API-v2 4.4.
- Produces: `<BookingForm disabled onBooked />` calling `onBooked(pickupDetail)` after a 201.

- [ ] **Step 1: Run the check to see it fail**

Run: `grep -c "serial_numbers" src/BookingForm.jsx`
Expected: `0`.

- [ ] **Step 2: Implement**

```jsx
import { useState } from 'react'
import { api, errorMessages, parseSerials, todayLocal } from './lib.js'

const EMPTY = { pickup_date: '', estimated_device_count: '', serials: '' }

export default function BookingForm({ disabled, onBooked }) {
  const [form, setForm] = useState(EMPTY)
  const [fieldErrors, setFieldErrors] = useState({})
  const [formError, setFormError] = useState(null)
  const [saving, setSaving] = useState(false)
  const serialCount = parseSerials(form.serials).length

  function update(field, value) {
    setForm(prev => ({ ...prev, [field]: value }))
  }

  async function submit(e) {
    e.preventDefault()
    setSaving(true)
    setFormError(null)
    try {
      const pickup = await api('/pickups', 'POST', {
        pickup: {
          pickup_date: form.pickup_date,
          estimated_device_count: form.estimated_device_count,
          serial_numbers: parseSerials(form.serials),
        },
      })
      setForm(EMPTY)
      setFieldErrors({})
      onBooked(pickup)
    } catch (err) {
      setFieldErrors(err.fields ?? {})
      if (!err.fields) setFormError(`Couldn't book the pickup. ${err.message}`)
    } finally {
      setSaving(false)
    }
  }

  // "Pickup date can't be in the past", under its own input.
  function errorFor(field) {
    if (!fieldErrors[field]) return null
    return <p id={`${field}-error`} className="field-error">{errorMessages({ [field]: fieldErrors[field] }).join('. ')}</p>
  }

  function describedBy(field, hintId) {
    return [hintId, fieldErrors[field] && `${field}-error`].filter(Boolean).join(' ') || undefined
  }

  return (
    <section className="shell" aria-labelledby="book-heading">
      <form className="core form" onSubmit={submit} noValidate>
        <h2 id="book-heading">Book a pickup</h2>

        <div className="field">
          <label htmlFor="pickup_date">Pickup date</label>
          <input id="pickup_date" type="date" min={todayLocal()} value={form.pickup_date}
            onChange={e => update('pickup_date', e.target.value)}
            aria-invalid={Boolean(fieldErrors.pickup_date)} aria-describedby={describedBy('pickup_date')} />
          {errorFor('pickup_date')}
        </div>

        <div className="field">
          <label htmlFor="estimated_device_count">Estimated number of devices</label>
          <input id="estimated_device_count" type="number" min="1" max="10000" step="1" inputMode="numeric"
            value={form.estimated_device_count} onChange={e => update('estimated_device_count', e.target.value)}
            aria-invalid={Boolean(fieldErrors.estimated_device_count)}
            aria-describedby={describedBy('estimated_device_count', 'estimate-hint')} />
          <p id="estimate-hint" className="hint">A rough count is fine.</p>
          {errorFor('estimated_device_count')}
        </div>

        <div className="field">
          <label htmlFor="serials">Serial numbers (optional)</label>
          <textarea id="serials" rows={5} spellCheck={false} value={form.serials}
            onChange={e => update('serials', e.target.value)}
            aria-invalid={Boolean(fieldErrors.serial_numbers)}
            aria-describedby={describedBy('serial_numbers', 'serials-hint')} />
          <p id="serials-hint" className="hint">
            One per line, {serialCount} listed. Leave it blank and Revivn records serials when the devices arrive.
          </p>
          {fieldErrors.serial_numbers && (
            <ul id="serial_numbers-error" className="field-error">
              {fieldErrors.serial_numbers.map(message => <li key={message}>{message}</li>)}
            </ul>
          )}
        </div>

        {formError && <p className="field-error" role="alert">{formError}</p>}
        <button className="btn btn-primary" disabled={saving || disabled}>{saving ? 'Booking…' : 'Book pickup'}</button>
      </form>
    </section>
  )
}
```

- [ ] **Step 3: Run the checks**

Run: `grep -c "serial_numbers" src/BookingForm.jsx; grep -c "setForm({ ...form" src/BookingForm.jsx; npm run lint && npm run build`
Expected: a number greater than 0; `0`; lint clean; `built in`.

- [ ] **Step 4: Commit**

```bash
git add frontend && git commit -m "feat(frontend): booking form with optional serials"
```

### Task F5: Warehouse simulator (demo) panel

**Files:**
- Modify: `frontend/src/WarehousePanel.jsx` (replace the stub)

**Interfaces:**
- Consumes: `DEVICE_LABELS`; the `onAction` contract from F3; API-v2 4.6, 4.7, 4.8 and the "next actions" table in 2.3.
- Produces: element ids `warehouse-heading`, `wh-serial`, `wh-device-<id>`.

- [ ] **Step 1: Run the check to see it fail**

Run: `grep -c "Warehouse simulator (demo)" src/WarehousePanel.jsx`
Expected: `0`.

- [ ] **Step 2: Implement**

```jsx
import { useState } from 'react'
import { DEVICE_LABELS } from './lib.js'

const TERMINAL = ['resold', 'donated', 'recycled']

// DEMO ONLY. In production these steps come from Revivn's warehouse tools,
// never from the customer's screen. The panel exists so the read-only
// customer view can be shown updating live.
export default function WarehousePanel({ pickup, rowError, onAction }) {
  const [serial, setSerial] = useState('')
  const [model, setModel] = useState('')
  const openDevices = pickup.devices.filter(d => !TERMINAL.includes(d.status))
  const errorFor = key => rowError?.key === key && <p className="row-error" role="alert">{rowError.message}</p>

  // Collect, receive and check-in record a physical fact, so no confirm.
  // Sanitize and dispose are irreversible decisions, so they confirm first.
  function deviceAction(device, action, body, confirmText) {
    return onAction({
      key: `device-${device.id}`,
      pickupId: pickup.id,
      path: `/devices/${device.id}/${action}`,
      body,
      confirmText,
      focusIds: [`wh-device-${device.id}`, 'warehouse-heading'],
    })
  }

  function dispose(device, outcome, label) {
    return deviceAction(device, 'dispose', { outcome }, `Mark ${device.serial_number} as ${label.toLowerCase()}? This is final.`)
  }

  async function addDevice(e) {
    e.preventDefault()
    const ok = await onAction({
      key: 'add-device',
      pickupId: pickup.id,
      path: `/pickups/${pickup.id}/devices`,
      body: { device: { serial_number: serial, model } },
      focusIds: ['wh-serial'],
    })
    if (ok) {
      setSerial('')
      setModel('')
    }
  }

  return (
    <section className="shell simulator" aria-labelledby="warehouse-heading">
      <div className="core">
        <p className="demo-tag">Demo only</p>
        <h2 id="warehouse-heading" tabIndex={-1}>Warehouse simulator (demo)</h2>
        <p className="hint">
          Customers can't do any of this. In production, Revivn's warehouse team records these steps.
          They're here so you can watch the customer view update.
        </p>

        {pickup.status === 'cancelled' && <p className="state">This pickup was cancelled. Nothing to simulate.</p>}

        {pickup.status === 'scheduled' && (
          <>
            <div className="detail-actions">
              <button type="button" className="btn btn-secondary"
                onClick={() => onAction({ key: 'collect', pickupId: pickup.id, path: `/pickups/${pickup.id}/collect`, focusIds: ['warehouse-heading'] })}>
                Mark pickup collected
              </button>
            </div>
            {errorFor('collect')}
          </>
        )}

        {pickup.status === 'collected' && (
          <>
            <form className="add-device" onSubmit={addDevice}>
              <div className="field">
                <label htmlFor="wh-serial">Unlisted device: serial number</label>
                <input id="wh-serial" value={serial} maxLength={50} onChange={e => setSerial(e.target.value)} />
              </div>
              <div className="field">
                <label htmlFor="wh-model">Model (optional)</label>
                <input id="wh-model" value={model} maxLength={100} onChange={e => setModel(e.target.value)} />
              </div>
              <button className="btn btn-secondary">Check in device</button>
            </form>
            {errorFor('add-device')}

            {openDevices.length === 0 ? (
              <p className="state">No devices waiting for a step.</p>
            ) : (
              <table className="devices">
                <thead>
                  <tr>
                    <th scope="col">Serial number</th>
                    <th scope="col">Status</th>
                    <th scope="col">Next step</th>
                  </tr>
                </thead>
                <tbody>
                  {openDevices.map(d => (
                    <tr key={d.id}>
                      <th scope="row" id={`wh-device-${d.id}`} tabIndex={-1} className="serial">{d.serial_number}</th>
                      <td><span className={`pill tone-${d.status}`}>{DEVICE_LABELS[d.status]}</span></td>
                      <td className="step-actions">
                        {d.status === 'expected' && (
                          <button type="button" className="btn btn-secondary" onClick={() => deviceAction(d, 'receive')}>Receive</button>
                        )}
                        {d.status === 'received' && (
                          <>
                            <button type="button" className="btn btn-secondary"
                              onClick={() => deviceAction(d, 'sanitize', { sanitization_method: 'wipe' }, `Wipe the data on ${d.serial_number}? This can't be undone.`)}>
                              Sanitize: wipe
                            </button>
                            <button type="button" className="btn btn-secondary"
                              onClick={() => deviceAction(d, 'sanitize', { sanitization_method: 'destroy' }, `Destroy the drive in ${d.serial_number}? It can then only be recycled.`)}>
                              Sanitize: destroy
                            </button>
                          </>
                        )}
                        {d.status === 'sanitized' && (
                          <>
                            {d.sanitization_method === 'wipe' && (
                              <>
                                <button type="button" className="btn btn-secondary" onClick={() => dispose(d, 'resold', 'Resold')}>Resell</button>
                                <button type="button" className="btn btn-secondary" onClick={() => dispose(d, 'donated', 'Donated')}>Donate</button>
                              </>
                            )}
                            <button type="button" className="btn btn-secondary" onClick={() => dispose(d, 'recycled', 'Recycled')}>Recycle</button>
                          </>
                        )}
                        {errorFor(`device-${d.id}`)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </div>
    </section>
  )
}
```

- [ ] **Step 3: Run the checks**

Run: `grep -c "Warehouse simulator (demo)" src/WarehousePanel.jsx; npm run lint && npm run build`
Expected: `1`; lint clean; `built in`.

- [ ] **Step 4: Commit**

```bash
git add frontend && git commit -m "feat(frontend): labelled warehouse simulator panel"
```

### Task F6: Printable certificate

**Files:**
- Modify: `frontend/src/Certificate.jsx` (replace the stub)

**Interfaces:**
- Consumes: `api`, `errorText`, `formatDate`, `formatDateTime`, `DEVICE_LABELS`, `METHOD_LABELS`; API-v2 4.9; `.certificate` / `.no-print` print CSS from F2.
- Produces: `<Certificate pickupId onClose />`, focusing `cert-heading` when loaded.

- [ ] **Step 1: Run the check to see it fail**

Run: `grep -c "window.print" src/Certificate.jsx`
Expected: `0`.

- [ ] **Step 2: Implement**

```jsx
import { useEffect, useRef, useState } from 'react'
import { api, DEVICE_LABELS, errorText, formatDate, formatDateTime, METHOD_LABELS } from './lib.js'

// The customer's proof. Printing uses the browser (window.print + a print
// stylesheet), which also gives "Save as PDF" without a PDF library.
export default function Certificate({ pickupId, onClose }) {
  const [cert, setCert] = useState(null)
  const [error, setError] = useState(null)
  const heading = useRef(null)

  useEffect(() => {
    let ignore = false
    api(`/pickups/${pickupId}/certificate`)
      .then(data => { if (!ignore) setCert(data) })
      .catch(err => { if (!ignore) setError(errorText(err)) })
    return () => { ignore = true }
  }, [pickupId])

  useEffect(() => {
    if (cert) heading.current?.focus()
  }, [cert])

  return (
    <section className="shell certificate-shell" aria-labelledby="cert-heading">
      <div className="core certificate">
        {error && <p className="row-error" role="alert">{error}</p>}
        {!cert && !error && <p className="state">Loading certificate…</p>}

        {cert && (
          <>
            <h2 id="cert-heading" ref={heading} tabIndex={-1}>Certificate of data destruction</h2>
            <dl className="cert-facts">
              <dt>Customer</dt><dd>{cert.customer_name}</dd>
              <dt>Pickup</dt><dd>#{cert.pickup_id}, {formatDate(cert.pickup_date)}</dd>
              <dt>Standard</dt><dd>{cert.standard}</dd>
              <dt>Issued</dt><dd>{formatDateTime(cert.issued_at)}</dd>
            </dl>
            <table>
              <thead>
                <tr>
                  <th scope="col">Serial number</th>
                  <th scope="col">Model</th>
                  <th scope="col">Method</th>
                  <th scope="col">Sanitized</th>
                  <th scope="col">Outcome</th>
                </tr>
              </thead>
              <tbody>
                {cert.devices.map(d => (
                  <tr key={d.serial_number}>
                    <th scope="row" className="serial">{d.serial_number}</th>
                    <td data-label="Model">{d.model || '—'}</td>
                    <td data-label="Method">{METHOD_LABELS[d.sanitization_method]}</td>
                    <td data-label="Sanitized">{formatDateTime(d.sanitized_at)}</td>
                    <td data-label="Outcome">{d.status === 'sanitized' ? 'Awaiting outcome' : DEVICE_LABELS[d.status]}</td>
                  </tr>
                ))}
              </tbody>
            </table>
            <p className="hint">
              {cert.devices.length} devices. Demo document generated by Pickup Tracker, not an official Revivn certificate.
            </p>
          </>
        )}

        <div className="detail-actions no-print">
          {cert && <button type="button" className="btn btn-primary" onClick={() => window.print()}>Print or save as PDF</button>}
          <button type="button" className="btn btn-secondary" onClick={onClose}>Close certificate</button>
        </div>
      </div>
    </section>
  )
}
```

- [ ] **Step 3: Run the checks**

Run: `grep -c "window.print" src/Certificate.jsx; npm run lint && npm run build && node --test src/lib.test.js`
Expected: `1`; lint clean; `built in`; `# fail 0`.

- [ ] **Step 4: Commit**

```bash
git add frontend && git commit -m "feat(frontend): printable certificate of data destruction"
```

---

# Track DOCS (after BACKEND and FRONTEND are both done)

### Task D1: Integration check, then README rewrite

**Files:**
- Modify: `README.md` (whole file)

**Interfaces:**
- Consumes: the running app, `docs/PRD-v2.md`, `docs/API-v2.md`.

- [ ] **Step 1: Start both servers**

Terminal 1 (Git Bash): `cd /c/Users/vp141/pickup-tracker/backend && export PATH=/c/Ruby34-x64/bin:$PATH && ruby bin/rails db:seed && ruby bin/rails server`
Terminal 2: `cd /c/Users/vp141/pickup-tracker/frontend && npm run dev`

- [ ] **Step 2: API smoke test against the contract**

Run in a third terminal:
```bash
B=http://localhost:3000
curl -s $B/customer
curl -s $B/pickups | head -c 400; echo
TODAY=$(curl -s $B/pickups | ruby -rjson -e 'p JSON.parse(STDIN.read).find { |x| x["status"] == "scheduled" && x["device_counts"]["expected"] == 3 }["id"]')
curl -s -o /dev/null -w "%{http_code}\n" $B/pickups/$TODAY/certificate
curl -s -X POST $B/pickups/$TODAY/collect | head -c 200; echo
curl -s -o /dev/null -w "%{http_code}\n" -X DELETE $B/pickups/$TODAY
curl -s -X POST -H "Content-Type: application/json" -d '{}' $B/pickups
```
Expected, in order: `{"id":...,"name":"Acme Corp"}`; a JSON array starting with the `today + 6` pickup; `409`; a pickup with `"status":"collected"`; `404`; `{"error":"param is missing ..."}`. Then re-run `ruby bin/rails db:seed` to reset.

- [ ] **Step 3: Browser checklist at http://localhost:5173**

Every line must hold; fix the owning track's code if not.
1. Header reads "Acme Corp: your pickups"; 6 pickups listed, newest date first; the cancelled one shows a grey "Cancelled" pill.
2. Book: today's date, estimate 2, serials `qa-serial-1` and `qa-serial-2`. Notice says "Pickup booked for Nov 1, 2026 with 2 serial numbers." Detail opens with 2 rows `QA-SERIAL-1`, `QA-SERIAL-2`, status Expected; focus is on the detail heading.
3. Book again with `qa-serial-1`: "QA-SERIAL-1 is already registered" under the serials field. Book with yesterday's date: "Pickup date can't be in the past".
4. Open the 2026-11-07 pickup and click "Mark pickup collected": "Pickup date is in the future, so the pickup can't be collected yet" appears next to the button.
5. Open today's seeded pickup. Collect, Receive all 3, Sanitize one by destroy (confirm dialog appears) and two by wipe. The destroyed one offers only Recycle. Dispose all 3. Progress shows Complete; the summary figures update without reload.
6. "View certificate of data destruction" is disabled before step 5 finishes and enabled after. The certificate lists 3 serials with method, date and outcome. "Print or save as PDF" opens a print preview showing only the certificate.
7. Stale state: open the 2026-11-07 pickup, run `curl -s -X POST localhost:3000/pickups/<its id>/cancel` in a terminal, then click "Cancel pickup" in the browser and confirm. The message "Status can't go from cancelled to cancelled" appears next to the button, and the panel refreshes to show Cancelled.
8. Add a device in the simulator with a 50-character serial of `W`s on a collected pickup: the serial wraps; the page never scrolls sideways at 1280px or at 375px (DevTools device mode).
9. Keyboard only: Tab reaches every button; after Receive, focus lands on that device's serial cell in the simulator; after the last outcome removes the row, focus lands on the simulator heading. Every button shows text and is at least 32px tall.
10. Stop Rails and reload: banner "Couldn't load your pickups..." with Retry, figures show "—", Book pickup is disabled.

- [ ] **Step 4: Rewrite `README.md`**

Replace the whole file with the content below. In the Tests section, write the backend run count from the `ruby bin/rails test` output where it says `<runs>`.

````markdown
# Pickup Tracker

A small Rails + React app showing **a Revivn customer's view** of their hardware pickups: book a pickup, follow every device through data sanitization to resale, donation or recycling, and print a certificate of data destruction. I built it before my Revivn interview to learn Rails and React. It is a learning project, not a production system.

Why it looks like this: [docs/PRD-v2.md](docs/PRD-v2.md). Exact API: [docs/API-v2.md](docs/API-v2.md). Build plan: [docs/PLAN-v2.md](docs/PLAN-v2.md). The four audits that drove v2 are in [docs/audit/](docs/audit/).

## What it does

- **Customer view (Acme Corp's IT admin).** Pickups list, newest first, with progress and estimate vs checked-in counts; totals by device status; a detail panel with progress steps and a device table.
- **Book a pickup:** date, estimated device count, optional serial numbers (one per line). Every pickup starts `scheduled`.
- **Per-device lifecycle:** `expected → received → sanitized → resold | donated | recycled`. A device can't reach an outcome without being sanitized, a destroyed drive can only be recycled, and nothing moves backward.
- **Progress is derived,** not stored: `collected → processing → complete` comes from the devices.
- **Certificate of data destruction** per pickup, available once every device is sanitized, printed with the browser.
- **Cancel, never delete,** and only while scheduled.
- **Warehouse simulator (demo):** a clearly labelled panel that plays Revivn's warehouse, so the read-only customer view can be shown updating.

What is verified about Revivn and what is my inference is labelled in the PRD. Per-device certificates are what I'd expect customers need, not a confirmed Revivn feature.

## Stack

| Layer | Tech |
|---|---|
| Backend | Ruby 3.4, Rails 8.1 (API-only), SQLite |
| Frontend | React 19, Vite 6, plain `fetch`, no UI library |
| Tests | Minitest; Node's built-in `node --test` for frontend helpers |

## Run it locally

You need Ruby 3.4 (see `backend/.ruby-version`) and Node.js 20 or newer. On Windows, use RubyInstaller with the DevKit and run `ruby bin/rails ...` if `bin/rails` doesn't run directly.

```sh
# terminal 1
cd backend
bundle install
bin/rails db:prepare db:seed
bin/rails server

# terminal 2
cd frontend
npm install
npm run dev
```

Open the URL Vite prints (usually http://localhost:5173). `db:seed` rebuilds the demo data with dates relative to today; run it again to reset.

## 90-second demo

1. Open today's pickup (3 expected serials).
2. In the Warehouse simulator: Mark pickup collected, Receive each device, sanitize one by destroy and two by wipe. The destroyed one is only offered Recycle.
3. Give each an outcome and watch progress reach Complete.
4. View the certificate and print it.

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/customer` | The demo customer |
| GET | `/pickups` | List, newest date first (max 200) |
| GET | `/pickups/:id` | One pickup with its devices |
| POST | `/pickups` | Book (customer) |
| POST | `/pickups/:id/cancel` | Cancel while scheduled (customer) |
| POST | `/pickups/:id/collect` | Warehouse simulator |
| POST | `/pickups/:pickup_id/devices` | Warehouse simulator: unlisted device at intake |
| POST | `/devices/:id/receive` | Warehouse simulator |
| POST | `/devices/:id/sanitize` | Warehouse simulator (`wipe` or `destroy`) |
| POST | `/devices/:id/dispose` | Warehouse simulator (`resold`, `donated`, `recycled`) |
| GET | `/pickups/:id/certificate` | Certificate; 409 until every device is sanitized |

Every action returns the whole updated pickup. Errors: 422 `{ field: [messages] }`, 404 `{ error }`, 409 `{ error }`. Full shapes in [docs/API-v2.md](docs/API-v2.md).

## Tests

```sh
cd backend && bin/rails test        # <runs> tests: every model rule and every endpoint, including 404/409/422
cd frontend && node --test src/lib.test.js   # api() and the pure helpers
cd frontend && npm run lint && npm run build
```

There is no React component test suite: adding Vitest and Testing Library would mean new packages. UI behaviour is checked with the browser checklist in docs/PLAN-v2.md (Task D1).

## Key decisions

**`current_customer` instead of auth.** Every query starts from one method that returns the seeded customer. A real login replaces that method and nothing else. Another customer's pickup answers 404.

**Progress derived from devices.** Only `scheduled`, `collected` and `cancelled` are stored. `processing` and `complete` are computed, so the pickup can't disagree with its devices.

**A `TRANSITIONS` map per model, shared through one small concern.** Each model lists its allowed moves; `move_to` refuses anything else, including repeats. The compliance rule (only a wiped device is reused) is also a database check constraint.

**Action endpoints instead of `PATCH status`.** `POST /devices/:id/sanitize` says what happened and who may do it; a free status field let v1 skip straight to "donated".

**Cancel, never delete.** Chain-of-custody records are kept.

**Browser print instead of a PDF gem.** `window.print()` plus a print stylesheet already saves a PDF.

**Vite proxy instead of rack-cors, SQLite, API-only Rails.** One origin in development, no database server, Rails returns JSON and React owns the UI.

## What I'd do next

- Login and roles (customer vs Revivn operator), replacing `current_customer` and the simulator.
- An audit log of who sanitized each device, which a real certificate needs.
- Site address, contact and time window on booking; edit or reschedule while scheduled.
- A `data_bearing` flag so monitors skip sanitization.
- Serial search ("where is C02XK1?"), CSV export, pagination.
````

- [ ] **Step 5: Verify the README**

Run: `grep -c "company\|picked_up\|refurbished" /c/Users/vp141/pickup-tracker/README.md; grep -c "<runs>" /c/Users/vp141/pickup-tracker/README.md`
Expected: `0` and `0`.

- [ ] **Step 6: Commit**

```bash
git add README.md && git commit -m "docs: README for v2 customer view"
```

---

## Self-review (done while writing)

- **Spec coverage:** migrations (B1 to B3); sanitize-before-outcome, destroyed→recycled only, no backward moves (B3); no past date on create, status not settable on create (B2, B5); action endpoints and no PATCH/DELETE (B5, B6); cancel instead of delete (B2, B6); single `current_customer` (B1, B5, B6); seeds consistent with 2026-11-01 (B8); upcoming-first order (B5); certificate with 409 (B4, B7). Frontend: list + detail + device table + progress (F3), certificate with `window.print()` (F6), booking form with optional serials and estimate (F4), labelled simulator (F5), functional setState (F3, F4), server errors near the row (F3, F5), refetch after failure (F3 `refresh`), wrapping (F2), focus management (F3 `focusById`, F5, F6), 32px labelled targets (F2), confirm before irreversible actions (F3 cancel, F5 sanitize/dispose). Address/contact: cut per the audits (PRD cut list).
- **Placeholder scan:** none. The only blank is `<runs>` in the README, filled from a measured test run and checked by grep in D1 Step 5.
- **Name consistency:** `move_to`, `collect`, `cancel`, `receive`, `sanitize(method)`, `dispose(outcome)`, `as_json_with_devices`, `certificate_available?`, `device_counts`; frontend `runAction`, `upsertPickup`, `errorText`, `focusById`; ids `detail-heading`, `warehouse-heading`, `wh-serial`, `wh-device-<id>`, `cert-heading`; rowError keys `list-`, `pickup-`, `collect`, `add-device`, `device-`. Same spelling in every task.
