# Decisions

Short decision records for Pickup Tracker v2. Each one says what I chose, what I passed on, and what the choice costs. Scope and rulings: [PRD-v2.md](PRD-v2.md) and [audit/RULING-QUESTIONS.md](audit/RULING-QUESTIONS.md). ADR-001 to ADR-008 are dated 2026-11-01; ADR-009 to ADR-011 (from [audit/FIX-LIST-v3.md](audit/FIX-LIST-v3.md)) are dated 2026-11-02. All accepted.

---

## ADR-001: Track the lifecycle per device, not per pickup

**Context.** v1 had one status per pickup (`scheduled → picked_up → refurbished → donated`) and a device count. A customer's auditor asks about each serial number, not about a batch: was its data destroyed, how, when, and where did it end up. A count can't answer that.

**Decision.** A `devices` table, one row per serial number, with its own status: `expected → received → sanitized → resold | donated | recycled`, plus `expected → not_received` (ADR-009). Sanitize records `sanitization_method` (`wipe` or `destroy`) and `sanitized_at`. No transition skips `sanitized`, and a destroyed drive can only be recycled (`backend/app/models/device.rb`).

Devices enter two ways (ruling Q1, option C): serials listed at booking become `expected`, and the warehouse can add an unlisted device at intake, which starts `received`. The pickup keeps `estimated_device_count` because many customers won't have a serial list.

**Alternatives.** Keep a per-pickup status and add counters: rejected, since it still can't list serials on a certificate. Serials only at intake (ruling option B): it works, but loses the "nothing went missing between my office and Revivn" check the customer gets from listing serials up front.

**Consequences.** One more table and model. The certificate can list every serial. Every device is treated as data-bearing. A `data_bearing` flag can come later, when monitors and peripherals show up.

---

## ADR-002: Derive pickup progress from its devices

**Context.** Once devices have their own status, a stored pickup status like "processing" or "complete" can drift out of sync with the rows it summarizes.

**Decision.** Store only what a person decides: `scheduled`, `collected`, `cancelled`. `Pickup#progress` computes the rest. A collected pickup reads `complete` when every device has an outcome or is `not_received` (ADR-009), `processing` once any device is past `expected`, and `collected` otherwise. Ruling Q2 was 4-0.

**Alternatives.** A full stored status updated by callbacks on device changes. That means more code, plus a class of bug (a missed callback) that the derived version can't have.

**Consequences.** The list endpoint counts devices with one grouped SQL query (`Pickup.with_device_counts`) and preloads certificates, so it never loads device rows; a test pins it at 4 queries. Progress is still recomputed on every read, which is fine at 200 rows. With much more data I'd add counter columns.

---

## ADR-003: Read-only customer view plus a labelled warehouse simulator

**Context.** The product is the customer's view. A customer can't know when Revivn received or wiped a device, so they shouldn't be able to click those buttons. v1 let them jump straight to "donated". The demo still has to show the view changing.

**Decision.** The customer can book and cancel, nothing else. A separate panel titled "Warehouse simulator (demo)" with a "Demo only" tag calls the warehouse endpoints (collect, add device, receive, sanitize, dispose). Ruling Q3 was 4-0. The endpoints are actions (`POST /devices/:id/sanitize`), not a free `PATCH status`, and every one returns the whole updated pickup, so the client replaces a single object.

**Alternatives.** Two tabs, "Customer portal" and "Revivn ops". That would make the app look like an ops tool again, which is the problem the product audit flagged.

**Consequences.** The warehouse endpoints have no access control. They're scoped to `current_customer` like everything else. With roles they would move behind a Revivn-operator check, and the simulator would go away.

---

## ADR-004: String status columns and one small forward-only concern

**Context.** Both Pickup and Device need "status only moves along these edges". The plan also required every line to be explainable in an interview, with no state-machine gem.

**Decision.** Plain string columns. Each model declares `STATUSES` and a `TRANSITIONS` hash. `ForwardOnly` (`backend/app/models/concerns/forward_only.rb`) adds two guards:

- `move_to(new_status)`, used by the action methods, refuses any move that isn't in the map, including repeats like `sanitized → sanitized`, so a second sanitize can't swap the method.
- A validation on update that checks `status_was → status` against the same map, so a direct `update(status: ...)` from the console or seeds is refused too.

**Alternatives.** Rails `enum` with integers: the database values are unreadable, and it adds predicate and bang methods I don't need. AASM or a similar gem: no new gems, and it hides the rules behind a DSL.

**Consequences.** The rules are about 25 lines you can read top to bottom. `update_column` and raw SQL skip validations. The seeds use `update_column` once, to backdate `sanitized_at`, and never for status.

---

## ADR-005: Check constraints in the database for the compliance rules

**Context.** Model validations protect the app's write paths, but not raw SQL, `update_column`, or a future second writer.

**Decision.** SQLite check constraints (`backend/db/schema.rb`) for the rules that matter most:

- `devices_status_allowed` and `pickups_status_allowed`: status must be a known value.
- `devices_method_allowed`: the method is null, `wipe`, or `destroy`.
- `devices_reuse_needs_wipe`: a `resold` or `donated` device must have `sanitization_method = 'wipe'`. This is the data-security rule, so it gets the strongest guard.
- `pickups_estimate_range`: estimate between 1 and 10,000.

- `devices_sanitized_fields`: `expected`, `received` and `not_received` devices have no method and no time; every later status has both.
- `device_events_to_status_allowed`: history rows name a known status.

Plus `NOT NULL`, foreign keys, a partial unique index on `serial_number` (`WHERE status != 'not_received'`, ADR-009), and unique indexes on `certificates.pickup_id` and `certificates.number` (ADR-010).

**Alternatives.** Model validations only. That's simpler, but the rule I'd least want broken would depend on every future code path going through the model.

**Consequences.** Transition order (no skipping, no going back) is enforced in the model, not the database. A check constraint can't see the previous value. A trigger could, but I didn't think it was worth it here. Model tests write past the model with `insert_all` / `insert_all!` to prove the status, sanitized-fields, reuse, serial and one-certificate-per-pickup constraints fire.

---

## ADR-006: Vite dev proxy instead of CORS

**Context.** React runs on Vite (port 5173) and Rails on port 3000. Different ports mean a cross-origin browser request.

**Decision.** `frontend/vite.config.js` proxies `/customer`, `/pickups`, `/devices` and `/demo` to `http://localhost:3000`. The browser only ever talks to one origin, and the frontend calls relative paths.

**Alternatives.** The `rack-cors` gem with an allowed-origin list. That means a new gem and config for a problem that only exists in development.

**Consequences.** This only covers development. To deploy, I'd either serve the built frontend from the same host as Rails (same origin, still no CORS) or add `rack-cors` with a strict origin.

---

## ADR-007: No auth; every query starts from a seeded `current_customer`

**Context.** Login would take hours to set up and wouldn't show anything new about the domain. Tenancy still has to be real: one customer must never see another's devices.

**Decision.** `ApplicationController#current_customer` returns the seeded customer named "Acme Corp" (`Customer.find_by!`). Every controller query starts from it: `current_customer.pickups.find(id)` and `current_customer.devices.find(id)`. Another customer's pickup, device or certificate answers 404. Tests prove this with a second fixture customer, Globex.

**Alternatives.** Devise or the Rails 8 authentication generator: real, but outside a one-day scope. Unscoped queries plus a `customer_id` param: easy to get wrong, and it's the bug tenancy exists to prevent.

**Consequences.** Adding login means replacing that one method with a session lookup. The controllers shouldn't need to change. Until then, anyone who can reach the API acts as Acme Corp, so this must not be deployed as is.

---

## ADR-008: Demo reset is the one deliberate exception to "nothing is deleted"; dev/demo only

**Context.** Opening the app straight into a dashboard full of seeded data looked ready-made. A reviewer should start empty, and still be able to load the full story in one click and start over after playing with it.

**Decision.** `bin/rails db:seed` creates only the Acme Corp customer; `SAMPLE=1` also loads the sample pickups. `POST /demo/reset` deletes the current customer's pickups and devices in one transaction and, with `{"sample": true}`, rebuilds the sample data. Seeds and the endpoint both call `DemoData.reset!` (`app/models/demo_data.rb`), so the sample data lives in one place. The endpoint answers 404 in production unless `DEMO_MODE=1` (set only by the hosted demo in `render.yaml`, 2026-11-02) and always when `DEMO_RESET_DISABLED` is set, accepts only `Content-Type: application/json` (415 otherwise, so a plain cross-site form post can't trigger the delete) and only a boolean `sample` (422 otherwise). `db/seeds.rb` refuses to run in production unless `DEMO_MODE=1`, and loads samples only with `SAMPLE=1`. Sample serials are prefixed with `A<customer id>-`, so another customer's real device can never make the reset fail.

**Alternatives.** Keep seeding everything (looks ready-made). A frontend-only "sample mode" with fake data (the dashboard would no longer show what the API really does). A rake task only (the reviewer would need a terminal).

**Consequences.** This is the only code path that deletes records; everywhere else the lifecycle only moves forward. It is scoped to `current_customer`, so tenancy holds (tests prove Globex is untouched). It must stay off in any real production deploy: the environment check, the explicit `DEMO_MODE=1` opt-in for the throwaway hosted demo, and `DEMO_RESET_DISABLED` are the whole guard. The reset also deletes the customer's device history and certificates, the only other place those rows are ever removed.

---

## ADR-009: `not_received` for listed serials that never arrive; cancel releases serials

**Context.** A customer lists serials at booking, but not every listed device turns up. Before this, such a device stayed `expected` forever, which blocked `complete` and the certificate, and its serial stayed "registered", so a cancelled booking's serials could never be booked again.

**Decision.** A terminal device status `not_received`, reachable only from `expected`. The warehouse marks it (`POST /devices/:id/mark_not_received`) once the pickup is collected. Cancelling a pickup moves its `expected` devices to `not_received` through the same `move_to`, so the release is audited (ADR-011). A `not_received` device is never sanitized, counts as finished for `complete`, doesn't block the certificate, and is listed apart on it (`not_received_serials`). Serial uniqueness becomes a partial unique index `WHERE status != 'not_received'` plus a matching scoped validation, so a released serial can be booked again.

**Alternatives.** Delete the expected row on cancel: breaks "nothing is deleted". Keep it `expected` and exclude cancelled pickups from the uniqueness check: the rule would depend on a join, which a unique index can't express.

**Consequences.** Two device rows can share a serial when all but one are `not_received`. The certificate rule now also requires at least one sanitized device, so a pickup where nothing arrived is `complete` but has no certificate.

---

## ADR-010: The certificate is issued once, stored, and closes the pickup

**Context.** The certificate used to be built on every request with `issued_at` = now, so two prints of the same certificate disagreed, and a device checked in later could silently change a document a customer had already handed to an auditor.

**Decision.** A `certificates` table (`pickup_id` unique FK, `number` unique, `issued_at`). The first `GET /pickups/:id/certificate` while `certificate_available` creates it with `Certificate.create_or_find_by!`, which relies on the unique index, so two racing requests still end with one row; later requests return the stored one. The number is `CERT-` plus the pickup id zero-padded to 6 digits, known before the insert, so the column can be `NOT NULL`. Once a certificate exists the pickup is locked: adding a device or marking one not received answers 422 `{"pickup": ["is closed: certificate CERT-000042 already issued"]}`. The pickup summary carries `certificate_number`.

**Alternatives.** Keep computing it per request: the number and time would never be stable. Revoke and reissue on change: more states and a versioning story for a document the customer may already have shared.

**Consequences.** Outcomes (resold/donated/recycled) can still be recorded after issue; the certificate shows each device's current status, which only moves forward. The lock is a validation, not a row lock: a device added in the same instant as issuance could slip in (marked `ponytail:` in `device.rb`).

---

## ADR-011: Device history in an append-only `device_events` table, written in one place

**Context.** The product claims chain of custody, but each device only stored its current status plus `sanitized_at`. Nobody could say when a device was received or by which path it got where it is.

**Decision.** A `device_events` table (`device_id` FK, `from_status` nullable, `to_status`, `created_at`, check constraint on `to_status`). Rows are written in exactly two places: `ForwardOnly#move_to`, inside the same row lock and transaction as the status change, and `Device` `after_create` (from `nil`). `DeviceEvent#readonly?` makes saved rows immutable in the app. Device JSON gains `history` (oldest first); certificate rows gain `received_at` from it.

**Alternatives.** A versioning gem (PaperTrail): new gem, and it records every column change, not the lifecycle. Timestamp columns per status (`received_at`, ...): one migration per new status and no record of the path.

**Consequences.** One more query per pickup detail (devices preload their events). Rows written by raw SQL or `update_column` bypass history, as with every other model rule (ADR-004). Demo sample data is built through the real model methods; `move_to` takes an optional `at:` (default now) that stamps the event and, for a sanitize, `sanitized_at`, and a device's creation entry takes its `created_at`. So the sample history is backdated and chronological, while events are still written only by `move_to` and device creation.
