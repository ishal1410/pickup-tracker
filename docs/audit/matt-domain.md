# Domain model audit: pickup-tracker vs Revivn's real flow

Method: the `domain-modeling` skill (glossary, edge-case scenarios, checking the code against the domain).
Sources: README.md, `backend/app/models/pickup.rb`, `backend/app/controllers/pickups_controller.rb`, `backend/db/schema.rb`, `backend/db/seeds.rb`, `frontend/src/App.jsx`, `interview-prep/revivn/03-company.md`, and two pages fetched on 2026-11-01:

- **revivn.com (homepage), VERIFIED:** "Use the Revivn app to manage hardware pickups, track progress, and even see the impact of your donation." Also: "data-bearing devices undergo data sanitization that meets or exceeds DOD and NIST 800-88 standards." Also: "We partner with non-profit organizations to provide devices and tech access to underserved communities."
- **revivn.com/revivn-app, VERIFIED:** "Select your preferred pickup day and time in the app." Also: "Just tell us what to collect (or snap a photo), and we'll do the rest." Also: "Track your earnings in the app." Also: "It's your choice — keep the funds, or donate them to support nonprofit initiatives." Also: "Remote employees? Simply click to ship them a box..." Also: "View environmental impact reports...". The same page says customers can download **asset lists and certificates of destruction** that prove data was destroyed and assets were recycled responsibly. That sentence is paraphrased because it was too long to quote.

Labels: **VERIFIED** means it was read on the pages above. **INFERRED** means it is my reasoning about how an ITAD (IT asset disposition) business works. Revivn's site does not state it. Neither page says anything about serial numbers, grading, or the exact order of steps in the facility. Everything about the per-device lifecycle is therefore INFERRED, and every INFERRED point is a question to ask in the interview.

---

## 1. Ubiquitous language (glossary)

| Term | Meaning | Avoid saying | Source |
|---|---|---|---|
| **Customer** | The enterprise that owns the hardware and uses the Revivn App (for example Instacart or Lyft). It is the tenant: a customer sees only its own data. | "company" as a free-text string | VERIFIED (customers named in the JD); tenant boundary INFERRED |
| **Pickup** | One scheduled collection of hardware from one customer location on one date. It is a *logistics event*, not a processing step. | "batch" when you mean processing | VERIFIED ("schedule pickups", "preferred pickup day and time") |
| **Estimated count** | The number of devices the customer *says* it has when scheduling. It is a guess. | "device_count" as if it were the truth | INFERRED |
| **Device / Asset** | One physical piece of hardware (laptop, phone, monitor...) identified by its serial number. This is the unit that gets wiped, tracked, certified and dispositioned. | "laptop" (too narrow) | "track assets" and "asset lists" VERIFIED; serial as the identifier INFERRED |
| **Check-in / Receive** | Revivn logs a device against its pickup when it arrives, which records the *actual* contents. | | INFERRED |
| **Data-bearing** | A device that can hold customer data (laptops, phones, drives). Only data-bearing devices need sanitization. | | VERIFIED phrase ("data-bearing devices") |
| **Sanitization** | Destroying the data on a device to the "DOD and NIST 800-88" standard. There are two **methods**: *wipe* (software overwrite, after which the device can be reused) and *destroy* (physical shredding, after which it can only be recycled). | "refurbished" | Standard VERIFIED; two-method split INFERRED (NIST 800-88 defines Clear/Purge/Destroy) |
| **Certificate of destruction** | A document the customer can download. It proves the data on the listed assets was destroyed. It is the compliance deliverable. | "wipe certificate per pickup" (granularity unknown) | VERIFIED (asset lists + certificates of destruction); per-pickup granularity INFERRED |
| **Disposition** | The final outcome for one device. It is exactly one of **resold**, **donated** or **recycled**. | "refurbished" (a step, not an outcome) | Resale ("earnings"), donation and recycling VERIFIED as outcomes; one-per-device INFERRED |
| **Resold** | The device was sold again, and its value counts toward the customer's earnings. | | VERIFIED ("Track your earnings") |
| **Donated (device)** | The device went to a nonprofit through Tech Access. | | VERIFIED |
| **Donated (funds)** | The customer gives its *earnings* to nonprofits. This is a different thing from donating a device. | the plain word "donated" without saying which | VERIFIED ("keep the funds, or donate them") |
| **Recycled** | The device could not be reused, so it was broken down for materials. | | VERIFIED as a last resort (task brief: "recycling only what can't be reused") |
| **Refurbish** | Repair or clean a device so it can be resold or donated. It is an internal processing step *between* sanitization and disposition, never an end state. | as a status customers wait on | INFERRED |
| **Return kit** | A box shipped to a remote employee so they can send assets back. It is a second way devices come in, besides an on-site pickup. | | VERIFIED |

Language conflicts in the current code:
- `company` (a string) is acting as **Customer**. Two Pickups for "Acme" and "Acme Corp" would be two different customers.
- `device_count` mixes the **estimated count** with the actual number of devices received.
- `refurbished` and `donated` are *device* concepts applied to a *Pickup*.
- The app title says "Laptop", but Revivn handles all hardware ("hardware pickups").

---

## 2. Entities and relationships (demo-sized)

```
Customer 1 ──< Pickup 1 ──< Device
```

| Entity | Fields (minimum) | Notes |
|---|---|---|
| **Customer** | `name` (unique) | Replaces the `company` string. Gives "customers only see their own pickups" an obvious hook later. |
| **Pickup** | `customer_id`, `scheduled_on`, `estimated_device_count`, `status` (scheduled / collected / cancelled) | After collection, its progress is **derived from its devices** rather than stored. See section 3. |
| **Device** | `pickup_id`, `serial_number` (unique), `kind` (laptop/phone/monitor/other), `data_bearing` (bool), `status`, `sanitization_method` (wipe/destroy, nullable), `sanitized_at`, `disposition` (resold/donated/recycled, nullable), `dispositioned_at` | This is where the lifecycle and the compliance proof live. |

The **certificate of destruction is a view, not a table**. Render it on demand as `GET /pickups/:id/certificate`: the customer, the pickup, and for each serial number the method and the sanitized date. It is available only when every data-bearing device in the pickup is sanitized.

**Leave out of the demo** (say these aloud as "next", but don't build them):
- Users, auth, roles (customer vs Revivn operator)
- Locations and addresses
- Return kits and shipping
- Earnings in dollars, and fund donation
- Environmental impact (ESG) reports
- Grading and condition
- Refurbish as a tracked step
- Tech Access recipient organisations
- Status-history and audit table
- Automated workflows and API keys

Each one is real (most are VERIFIED features of the app). None of them changes the core model of Customer, Pickup and Device.

---

## 3. Lifecycle state machines

### Device (the one that matters)

```
received ──sanitize(wipe)────► sanitized(wipe) ──► resold | donated | recycled
   │
   ├──sanitize(destroy)──────► sanitized(destroy) ──► recycled          (only)
   │
   └──(not data-bearing)─────────────────────────────► resold | donated | recycled
```

States: `received`, `sanitized`, `resold`, `donated`, `recycled`. The last three are terminal.

| From | Event | To | Guard |
|---|---|---|---|
| (none) | check_in | received | pickup is `collected`; serial is unique |
| received | sanitize(method) | sanitized | device is data-bearing; set `sanitized_at` |
| sanitized | dispose(resold\|donated) | resold / donated | `sanitization_method == wipe` |
| sanitized | dispose(recycled) | recycled | always allowed |
| received | dispose(any) | resold / donated / recycled | **only if not data-bearing** |
| any terminal | anything | (rejected) | terminal states are final |

**Core invariant (the compliance rule):** a data-bearing device can never reach a disposition without first being sanitized. A physically destroyed device can only be recycled. (INFERRED, but it is the logical consequence of "wipe to NIST 800-88, then repurpose".)

Scenarios to test the model with:
- *A laptop's drive fails the wipe.* It gets `destroy` and then `recycled`. The model can express this, while the current model cannot.
- *The customer said 50 devices, 47 arrived.* `estimated_device_count` = 50 and devices.count = 47. The difference is visible, which matters to the customer. (INFERRED)
- *One pickup produces 30 resold, 10 donated, 7 recycled devices.* The current single `status` column cannot represent this at all.
- *A monitor with no storage.* It is not data-bearing, skips sanitize, and is not on the certificate.

### Pickup

```
scheduled ──collect──► collected ──(derived)──► processing ──(derived)──► complete
    │
    └──cancel──► cancelled
```

| From | Event | To | Guard |
|---|---|---|---|
| scheduled | collect | collected | date is today or earlier (optional) |
| scheduled | cancel | cancelled | replaces DELETE: keep the record |
| collected | (none) | *derived* `processing` | at least 1 device is not in a terminal state |
| collected | (none) | *derived* `complete` | at least 1 device, and every device is terminal. The certificate becomes available once every data-bearing device is sanitized. |

Only `scheduled / collected / cancelled` are stored. `processing` and `complete` are computed from the devices, so the pickup's progress can never disagree with its devices. This is the one decision worth an ADR if the user wants one ("Pickup progress is derived from Device states"): it is surprising without that context, and it is a real trade-off against a stored, denormalized status.

---

## 4. Gap table: current app vs correct model

| # | Area | Current app (file) | Correct model | Severity |
|---|---|---|---|---|
| 1 | Unit of work | `Pickup.status` goes to `refurbished` / `donated` (`pickup.rb` STATUSES) | Refurbish and disposition happen **per Device**. A Pickup only covers scheduling and collection. | **Critical** |
| 2 | Data sanitization | There is no wipe step, and `picked_up → donated` is allowed because "steps can be skipped" (README, `status_cannot_move_backward` only blocks backward moves) | Data-bearing devices *must* be sanitized before any disposition. Skipping it is the worst compliance bug possible for Revivn. | **Critical** |
| 3 | Device entity | Only `device_count` (an integer). No serial numbers. | A Device row per serial number. "Track assets" and "asset lists" are VERIFIED features. | **Critical** |
| 4 | Certificate of destruction | Missing (listed under "next" in the README) | A per-pickup certificate listing serials, method and date. This is the main thing customers download. | **High** |
| 5 | Outcomes | Only `donated`. No resold, no recycled. | resold / donated / recycled, one per device. Resale feeds "earnings". | **High** |
| 6 | "refurbished" as status | Treated as a stage the pickup can stop at (seed: Acme and Harbor are left at `refurbished`) | An internal step, not a state the customer tracks. Drop it from the demo. | **High** |
| 7 | Who changes status | The customer-facing UI lets anyone click any step (`App.jsx` stepper, `PATCH /pickups/:id` permits `status`) | The customer *schedules* and *cancels*. Revivn ops *collects, checks in, sanitizes and dispositions*. These are two different actors. | **High** |
| 8 | Delete | `DELETE /pickups/:id` hard-deletes, including donated pickups | Chain-of-custody records are never deleted. Only a `scheduled` pickup can be **cancelled**. | **High** |
| 9 | Customer | `company` free-text string (`schema.rb`) | A Customer entity, the future tenant boundary for auth | **Medium** |
| 10 | Count semantics | `device_count` is validated up to 10,000 as if it were exact | `estimated_device_count` (customer input) vs the actual count of devices checked in | **Medium** |
| 11 | Pickup progress | Stored status edited by hand | Derived from device states once collected | **Medium** |
| 12 | Dashboard | "devices-by-status" bar sums `device_count` by *pickup* status (`App.jsx` byStatus) | Count actual devices by device status/disposition, which is a real impact number | **Medium** |
| 13 | Scope words | "Laptop Pickup Tracker" | Hardware/asset (phones, monitors, peripherals) | **Low** |
| 14 | Return kits, earnings, ESG | Missing | Real (VERIFIED), but out of demo scope | **Low (mention only)** |

What is already right: forward-only transitions enforced in the model rather than in the UI; a 422 with field errors; validation in the model with tests. Keep all of these; they carry over directly to the Device machine.

---

## 5. Minimum v2 (about one day, explainable in 2 minutes)

**Pitch line:** "My first version tracked the pickup as if it were the thing being processed. Revivn's real unit is the device. Each serial number has to be sanitized before it can be resold, donated or recycled, and the customer's proof is a certificate built from those device records. So I moved the lifecycle down to Device and made the pickup's progress derived."

Build, in order:

1. **Migrations (about 1h).** `customers(name unique)`. On pickups: `customer_id` replaces `company`, `device_count` is renamed to `estimated_device_count`, and status becomes `scheduled|collected|cancelled`. New table `devices(pickup_id, serial_number unique, kind, data_bearing, status, sanitization_method, sanitized_at, disposition, dispositioned_at)`. Update the seeds so one pickup has a mix of resold, donated and recycled devices and one device was destroyed.
2. **Device model and its rules (about 2h, test first).** Add `sanitize!(method)` and `dispose!(outcome)` methods that enforce the table in section 3. Invariant tests: no disposition before sanitize for data-bearing devices; a destroyed device can only be recycled; terminal states are final; serial numbers are unique.
3. **Pickup changes (about 1h).** Add `collect!` and `cancel!` (only from scheduled), and `progress`, which computes processing or complete from the devices. Replace the destroy action with cancel.
4. **API (about 1h).** Keep `POST /pickups` (customer schedules) and add `POST /pickups/:id/cancel`. Add `POST /pickups/:id/collect` and `POST /pickups/:id/devices` (check in). Add `POST /devices/:id/sanitize` and `POST /devices/:id/dispose`, which return 422 with the rule that blocked the move. Add `GET /pickups/:id/certificate` (JSON, plus a simple printable page if time allows), which returns 409 until every data-bearing device is sanitized.
5. **React (about 2-3h).**
   - Pickups table showing the customer, the estimate vs actual count, and the derived progress.
   - A pickup detail panel with a device table (serial, kind, sanitized, disposition), using per-device action buttons in place of the pickup stepper.
   - A "Download certificate" button that stays disabled until the certificate is available.
   - A dashboard bar counting real devices by disposition.

Skip on purpose (say so out loud): auth and roles (the operator vs customer split is shown only by labelling the buttons "Revivn ops"), earnings in dollars, return kits, ESG, grading, status history.
Add when needed: auth and roles come first (gap 7), then an audit log of who sanitized each device, because that is what a real certificate needs.

Questions to ask Revivn in the interview (each tests an INFERRED assumption):
- Is the certificate per pickup, per device, or per reporting period?
- Do customers choose the disposition, or does Revivn decide based on device condition?
- How do you handle a mismatch between the estimated and actual device count?
