# Decisions

Short decision records for Pickup Tracker v2. Each one says what I chose, what I passed on, and what the choice costs. Scope and rulings: [PRD-v2.md](PRD-v2.md) and [audit/RULING-QUESTIONS.md](audit/RULING-QUESTIONS.md). All dated 2026-11-01, all accepted.

---

## ADR-001: Track the lifecycle per device, not per pickup

**Context.** v1 had one status per pickup (`scheduled → picked_up → refurbished → donated`) and a device count. A customer's auditor asks about each serial number, not about a batch: was its data destroyed, how, when, and where did it end up. A count can't answer that.

**Decision.** A `devices` table, one row per serial number, with its own status: `expected → received → sanitized → resold | donated | recycled`. Sanitize records `sanitization_method` (`wipe` or `destroy`) and `sanitized_at`. No transition skips `sanitized`, and a destroyed drive can only be recycled (`backend/app/models/device.rb`).

Devices enter two ways (ruling Q1, option C): serials listed at booking become `expected`, and the warehouse can add an unlisted device at intake, which starts `received`. The pickup keeps `estimated_device_count` because many customers won't have a serial list.

**Alternatives.** Keep a per-pickup status and add counters: rejected, since it still can't list serials on a certificate. Serials only at intake (ruling option B): it works, but loses the "nothing went missing between my office and Revivn" check the customer gets from listing serials up front.

**Consequences.** One more table and model. The certificate can list every serial. Every device is treated as data-bearing. A `data_bearing` flag can come later, when monitors and peripherals show up.

---

## ADR-002: Derive pickup progress from its devices

**Context.** Once devices have their own status, a stored pickup status like "processing" or "complete" can drift out of sync with the rows it summarizes.

**Decision.** Store only what a person decides: `scheduled`, `collected`, `cancelled`. `Pickup#progress` computes the rest. A collected pickup reads `complete` when every device has an outcome, `processing` once any device is past `expected`, and `collected` otherwise. Ruling Q2 was 4-0.

**Alternatives.** A full stored status updated by callbacks on device changes. That means more code, plus a class of bug (a missed callback) that the derived version can't have.

**Consequences.** The list endpoint loads devices for every pickup (`includes(:devices)`) to compute progress and counts. That's fine at 200 rows. With more data I'd add counter columns or a SQL aggregate.

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

Plus `NOT NULL`, foreign keys, and a unique index on `serial_number`.

**Alternatives.** Model validations only. That's simpler, but the rule I'd least want broken would depend on every future code path going through the model.

**Consequences.** Transition order (no skipping, no going back) is enforced in the model, not the database. A check constraint can't see the previous value. A trigger could, but I didn't think it was worth it here. I don't have tests that write past the model to prove the constraints fire.

---

## ADR-006: Vite dev proxy instead of CORS

**Context.** React runs on Vite (port 5173) and Rails on port 3000. Different ports mean a cross-origin browser request.

**Decision.** `frontend/vite.config.js` proxies `/customer`, `/pickups` and `/devices` to `http://localhost:3000`. The browser only ever talks to one origin, and the frontend calls relative paths.

**Alternatives.** The `rack-cors` gem with an allowed-origin list. That means a new gem and config for a problem that only exists in development.

**Consequences.** This only covers development. To deploy, I'd either serve the built frontend from the same host as Rails (same origin, still no CORS) or add `rack-cors` with a strict origin.

---

## ADR-007: No auth; every query starts from a seeded `current_customer`

**Context.** Login would take hours to set up and wouldn't show anything new about the domain. Tenancy still has to be real: one customer must never see another's devices.

**Decision.** `ApplicationController#current_customer` returns the seeded customer named "Acme Corp" (`Customer.find_by!`). Every controller query starts from it: `current_customer.pickups.find(id)` and `current_customer.devices.find(id)`. Another customer's pickup, device or certificate answers 404. Tests prove this with a second fixture customer, Globex.

**Alternatives.** Devise or the Rails 8 authentication generator: real, but outside a one-day scope. Unscoped queries plus a `customer_id` param: easy to get wrong, and it's the bug tenancy exists to prevent.

**Consequences.** Adding login means replacing that one method with a session lookup. The controllers shouldn't need to change. Until then, anyone who can reach the API acts as Acme Corp, so this must not be deployed as is.
