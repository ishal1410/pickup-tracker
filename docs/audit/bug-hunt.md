# Bug hunt: pickup-tracker v2 (scan only, no code edited)

Date: 2026-11-02, run at about 01:25-01:35 EST. Skill: bug-hunter (local-sequential, `--scan-only`).
Scope: `backend/app`, `config/routes.rb`, `db/`, `frontend/src/*.jsx`, `lib.js`, checked against `docs/API-v2.md`.
Method: read every source file, ran `bin/rails test` (95 runs, 0 failures), ran `bin/rails runner` probes inside a transaction that rolls back, used curl against :3000 and Playwright against :5173.
Cleanup: ran `POST /demo/reset {"sample":false}`, which returned `pickups_count: 0`, and `GET /pickups` returned `[]`. Acme was left empty.
Note: a second agent was using Acme's data at the same time (serials `QA-FLOW-*`). Every repro used its own `BH-*` serials or estimate values.

**Counts: 10 confirmed (0 Critical, 0 High, 5 Medium, 5 Low). 7 unconfirmed or not a bug.**

| # | Severity | Title | File:line |
|---|---|---|---|
| 1 | Medium | Sample reset returns 500 whenever another customer owns one of the fixed sample serials | `backend/app/models/demo_data.rb:84`, `:23-72` |
| 2 | Medium | Browsers west of Eastern get a prefilled date the server rejects ("can't be in the past") | `frontend/src/BookingForm.jsx:5,66`, `frontend/src/lib.js:64` |
| 3 | Medium | An open certificate keeps showing the old document (and Print) after it is revoked (409) | `frontend/src/Certificate.jsx:17` |
| 4 | Medium | After a reset from elsewhere, the certificate for a deleted pickup stays on screen | `frontend/src/App.jsx:55-60` |
| 5 | Medium | A ghost pickup appears after "Reset demo" when a detail request was in flight | `frontend/src/App.jsx:62-74, 107-128` |
| 6 | Low | Browsers east of Eastern flag today's pickup as "Past pickup date" and block picking server-today | `frontend/src/App.jsx:286`, `BookingForm.jsx:5,66` |
| 7 | Low | Double-clicking Receive (or any warehouse step) shows a false error | `frontend/src/WarehousePanel.jsx:106` (also 17-26) |
| 8 | Low | Double-clicking "Check in device" adds the device and also shows "already been taken" | `frontend/src/WarehousePanel.jsx:32-45, 83` |
| 9 | Low | Bad `serial_numbers` shapes are dropped silently and the API returns 201 | `backend/app/controllers/pickups_controller.rb:54` |
| 10 | Low | A 404 "Customer not found" on reset is reported as "Demo controls are turned off" | `frontend/src/App.jsx:122-124` |

---

## BUG-1 Medium: sample reset returns 500 when another customer holds a sample serial

- **File:line:** `backend/app/models/demo_data.rb:84` (`pickup.save!(validate: date >= Date.current)`), with the hard-coded serials at `:23-30, :42-48, :56, :63-65`. Serials are unique across all customers (`device.rb:23`, unique index on `devices.serial_number`).
- **Repro:** create another customer (Globex) with a device whose serial is `C02FK3Q1MD6R`, then run `DemoData.reset!(acme, sample: true)`, which is what `POST /demo/reset {"sample":true}` and `SAMPLE=1 db:seed` both call.
- **Expected:** reset loads the 6 samples, or returns a clear 4xx error.
- **Actual:** `ActiveRecord::RecordInvalid` is raised. Through HTTP that is a 500, and the UI says "Couldn't reset the demo. Something went wrong on the server (500)". The transaction does roll back (Acme keeps its old data), so nothing is lost. But the demo button is broken for good until the other row goes away. Past-dated sample pickups skip the pickup validation (`validate: false`), so the clash only shows up in `create_expected_devices` → `Device#create!`.
- **Proof** (`bin/rails runner`, rolled back):
  ```
  A: Globex holds C02FK3Q1MD6R (a sample serial). Acme reset sample:true ->
    RAISED ActiveRecord::RecordInvalid: Validation failed: Serial number has already been taken
    acme pickups after failed reset: 1
  after rollback: customers=["Acme Corp"] ...
  ```
- **Fix:** make the sample serials unique to the customer (for example prefix them with `customer.id`), or skip or rename serials that already exist. Rescue `RecordInvalid` in `DemoController#reset` and return 422 with the message.

## BUG-2 Medium: west-of-Eastern browsers get a prefilled date the server rejects

- **File:line:** `frontend/src/BookingForm.jsx:5` (prefill), `:66` (`min={todayLocal()}`), `frontend/src/lib.js:64` (`todayLocal` uses the browser zone). The server's "today" is `Date.current` in Eastern (`pickup.rb:120`, API-v2 section 1).
- **Repro:** between 00:00 and 03:00 ET, open the app in a Pacific browser, type an estimate of 1, and click "Book pickup" without changing the date.
- **Expected:** the default date (and the `min`) is the server's earliest valid date, so the default submit works.
- **Actual:** the prefill and `min` are `2026-11-01`, but server-today is `2026-11-02`. The server returns 422 "Pickup date can't be in the past". The window gets longer the further west the browser is (Hawaii: 5 h a day).
- **Proof** (Playwright, `timezoneId: 'America/Los_Angeles'`):
  ```
  browser Date: Sun Nov 01 2026 22:32:09 GMT-0800 (Pacific Standard Time)
  request body: {"pickup":{"pickup_date":"2026-11-01","estimated_device_count":"1","serial_numbers":[]}}
  HTTP 422 {"pickup_date":["can't be in the past"]}
  UI error under date field: [ "Pickup date can't be in the past" ]
  ```
- **Fix:** compute "today" in the server's zone, for example `new Intl.DateTimeFormat('en-CA', { timeZone: 'America/New_York' }).format(now)` in `todayLocal`, or have `GET /customer` return `today`. Use it for the prefill, `min`, and the `late` flag (BUG-6).

## BUG-3 Medium: a revoked certificate stays on screen with its Print button

- **File:line:** `frontend/src/Certificate.jsx:17`. The `.catch` sets `error` but never calls `setCert(null)`, so a refetch that fails leaves the old `cert` showing.
- **Repro:** create a collected pickup with one device, then receive and sanitize it (the certificate becomes available). In the UI open it, click "View certificate of data destruction", then use the warehouse panel to check in another device (`BH-CERT2`). The `version` prop changes and the certificate refetches.
- **Expected:** the certificate is gone or clearly invalidated, because the server now returns 409 (`certificate_available` false).
- **Actual:** the 409 message shows above the **old certificate table**, which lists 1 device when the pickup has 2. "Print or save as PDF" still works, so a customer can print a certificate that leaves out a device whose data was never destroyed.
- **Proof** (Playwright):
  ```
  certError: [ 'Certificate is available once every device in this pickup is sanitized' ],
  certRowsShown: [ 'BH-CERT1Not recordedWipedNov 2, 2026, 1:31 AMAwaiting outcome' ],
  printButtonVisible: true,
  serverCert: 409
  ```
  Screenshot: `C:/Users/vp141/AppData/Local/Temp/claude/C--Users-vp141/62210cf2-0021-467f-88ef-db63324b1853/scratchpad/cert-stale.png`
- **Fix:** in the catch, call `setCert(null)` as well (the `!cert && !error` branch then handles the display). Optionally close the certificate in `App` when `selected.certificate_available` turns false.

## BUG-4 Medium: after a reset from elsewhere, a deleted pickup's certificate stays on screen

- **File:line:** `frontend/src/App.jsx:55-60`. `forget()` clears `selected` but not `certificateId`. Combined with BUG-3, the old document stays visible.
- **Repro:** open a pickup's certificate. From another tab or curl, run `POST /demo/reset {"sample":false}`. Back in the first tab, do any action on the pickup (check in a device). The action gets a 404, then `refresh` gets a 404, then `forget(id)` runs.
- **Expected:** the detail panel and the certificate both close, with the notice "That pickup no longer exists."
- **Actual:** the detail panel closes, but the certificate for the now-deleted pickup stays mounted with its rows and the error "Pickup not found".
- **Proof** (Playwright):
  ```
  other tab reset: 200
  { detailPanelOpen: 0, certificateStillShown: 1,
    certRows: [ 'BH-CERT3Not recordedWipedNov 2, 2026, 1:32 AMAwaiting outcome' ],
    certError: [ 'Pickup not found' ], notice: [ 'That pickup no longer exists.' ] }
  ```
- **Fix:** in `forget`, add `setCertificateId(prev => (prev === id ? null : prev))`.

## BUG-5 Medium: ghost pickup after "Reset demo" when a detail request was in flight

- **File:line:** `frontend/src/App.jsx:62-74` (`openPickup` calls `setSelected` and `upsertPickup` without checking it is still current) and `:107-128` (`resetDemo` does not cancel or ignore requests already in flight). `runAction` and `refresh` have the same problem.
- **Repro:** create a pickup (estimate 47). Click its View button, and while `GET /pickups/:id` is slow (Playwright route delays the response 2.5 s), click "Reset demo" and accept.
- **Expected:** after reset the list is empty and the empty state shows.
- **Actual:** the server has 0 pickups, but the old detail response lands after the reload. The deleted pickup reappears as a list row, the detail panel and warehouse simulator open, and the empty state is hidden. It only clears after the user clicks an action and gets a 404.
- **Proof** (Playwright):
  ```
  { serverPickups: 0, emptyStateShown: 0,
    listRows: [ 'Nov 2, 20260 checked in (est. 47)ScheduledView' ],
    detailHeading: [ 'Pickup on Nov 2, 2026' ],
    notice: [ 'Demo reset. The account has no pickups.' ] }
  ```
- **Fix:** keep a `generation` ref that `resetDemo` (and the reload effect) increments. `openPickup`, `refresh` and `runAction` record it before `await` and drop the result if it changed. Also disable the booking form and action buttons while `resetting`.

## BUG-6 Low: east-of-Eastern browsers flag today's pickup as late and block picking server-today

- **File:line:** `frontend/src/App.jsx:286` (`late` compares to the browser's `todayLocal()`), `BookingForm.jsx:5,66`.
- **Repro:** browser in `Pacific/Kiritimati` with its clock at 2026-11-02 10:00 ET (Nov 3 locally). Create a scheduled pickup dated server-today (2026-11-02).
- **Expected:** no flag, because the pickup is due today on the server and can be collected. The date picker allows today.
- **Actual:** the row shows "Past pickup date, not collected yet", and `min` and the prefill are `2026-11-03`, so the native picker won't offer server-today.
- **Proof:**
  ```
  { min: '2026-11-03', prefill: '2026-11-03',
    row: 'Nov 2, 2026\nPast pickup date, not collected yet\n\t0 checked in (est. 53)\tScheduled\tView' }
  ```
- **Fix:** same as BUG-2 (use the server-zone "today").

## BUG-7 Low: double-clicking a warehouse step shows a false error

- **File:line:** `frontend/src/WarehousePanel.jsx:106` (Receive), and every step button at `:110-129`, plus "Mark pickup collected" at `:63`. Nothing disables them while a request is pending. `runAction` (`App.jsx:89-104`) has no in-flight guard.
- **Repro:** collected pickup with expected device `BH-DBL1`. Double-click "Receive".
- **Expected:** one receive, no error.
- **Actual:** the device is received, and a red alert "Status can't go from received to received" appears on its row. The server is correct: the second POST is a real illegal transition.
- **Proof:** `after dblclick Receive: [ "Status can't go from received to received" ]`
- **Fix:** keep a `pendingKey` state in `App` that `runAction` sets and clears. Disable buttons whose key is pending, or return early from `runAction` when that key is already in flight.

## BUG-8 Low: double-clicking "Check in device" adds the device and also shows an error

- **File:line:** `frontend/src/WarehousePanel.jsx:32-45` (`addDevice`), `:83` (the submit button is never disabled).
- **Repro:** same pickup. Type `BH-DBL2` and double-click "Check in device".
- **Expected:** one device added, input cleared, no error.
- **Actual:** the device is added (server shows `BH-DBL2:received`) and the input is cleared, but "Serial number has already been taken" stays under the form. That suggests the check-in failed.
- **Proof:**
  ```
  after dblclick Check in: [ 'Serial number has already been taken' ] server devices: [ 'BH-DBL1:received', 'BH-DBL2:received' ] serial input now: ""
  ```
- **Fix:** add a `saving` flag in `WarehousePanel` (like `BookingForm`'s) and disable the button while it is set, or use the shared in-flight guard from BUG-7.

## BUG-9 Low: bad `serial_numbers` shapes are dropped silently (201, no devices)

- **File:line:** `backend/app/controllers/pickups_controller.rb:54`. `params.expect(pickup: [..., serial_numbers: []])` quietly drops a non-array or nested value.
- **Repro:** `curl -X POST :3000/pickups -H 'Content-Type: application/json' -d '{"pickup":{"pickup_date":"2026-11-10","estimated_device_count":2,"serial_numbers":"BH-STR1"}}'`. Same result with `[["BH-NEST"]]`.
- **Expected:** API-v2 4.4 says `serial_numbers` is an "Array of strings". A wrong type should be a 422 (or 400), not lost data.
- **Actual:** 201 with `"devices":[]` and `device_counts.total: 0`. The serial the client sent is gone without any error.
- **Proof:**
  ```
  {"id":85,...,"device_counts":{...,"total":0},...,"devices":[]}  [HTTP 201]
  {"id":86,...,"devices":[]}  [HTTP 201]      # for [["BH-NEST"]]
  ```
- **Fix:** before `expect`, check `params.dig(:pickup, :serial_numbers)` and return 422 `{serial_numbers: ["must be a list of serial numbers"]}` when it is present and not an array of scalars.

## BUG-10 Low: a 404 "Customer not found" on reset is reported as "Demo controls are turned off"

- **File:line:** `frontend/src/App.jsx:122-124` treats every 404 as the production guard. API-v2 4.10 lists two different 404s: `{"error":"Not found"}` (production) and `{"error":"Customer not found"}` (database not seeded).
- **Repro:** Playwright route answers `POST /demo/reset` with the documented 404 `{"error":"Customer not found"}`, then click "Load sample data".
- **Expected:** "Customer not found" (seed the database), not a claim that the controls are disabled.
- **Actual:** `notice: [ 'Demo controls are turned off on this server.' ]`
- **Fix:** branch on `err.message === 'Not found'`, or show `err.message` for any other 404.

---

## Unconfirmed / checked and not a bug

1. **Server-side races (checked, no bug).** 2 parallel sanitize calls (wipe and destroy) on one device gave `wipe 200 / destroy 422 "can't go from sanitized to sanitized"`. 6 parallel bookings with one serial gave 1×201 and 5×422 `already registered`. 6 parallel add-device calls with one serial gave 1×201 and 5×422 `has already been taken`. `with_lock` plus Rails 8 SQLite IMMEDIATE transactions serialize these correctly.
2. **`RecordNotUnique` key mismatch on `POST /pickups` (not reproduced).** `application_controller.rb:18-20` always returns `{serial_number: [...]}`. If a unique-index race ever hit booking, the key would be `serial_number`, not the contract's `serial_numbers`, and `BookingForm.jsx:39` would show nothing. The 6-way race above never got past validation, so this is unreachable on SQLite as configured.
3. **Serials with non-breaking spaces (reproduced, but arguably within the contract).** Ruby `strip` keeps U+00A0, so `"NBSP123"` and `"NBSP123\u00A0"` both save as different devices (`stored serials: ["\"NBSP123\"", "\"NBSP123 \""]`). The UI path is safe (JS `trim()` removes NBSP). Only raw API clients are affected. Fix if wanted: strip with `/\A[[:space:]]+|[[:space:]]+\z/` in both `Pickup#serial_numbers=` and `Device` `normalizes`.
4. **`{"pickup":{}}` returns 400, not 422.** `params.expect` treats an empty hash as missing. API-v2 3.4 reserves 400 for a missing root key. Small contract deviation; the frontend always sends the keys.
5. **Malformed JSON returns Rails' dev debug 400 body**, not `{error}`. The contract doesn't cover malformed JSON. In production this is a plain 400.
6. **Cross-customer serial block (within the contract).** A Globex serial does block Acme (`"X is already registered"`), which also reveals that the serial exists elsewhere. API-v2 3.3 says "Unique across all devices" and `pickup.rb:128-130` documents the trade-off. Its real consequence is BUG-1.
7. **Grouped counts vs devices, N+1 test, seeds (checked, no bug).** `with_device_counts` and the per-pickup tally agree, and a test asserts it (`pickups_controller_test.rb:35`). The index runs 2 queries for 3 pickups plus the customer lookup, matching `assert_queries_count(3)`, and the test also checks that no `Device` rows load. Loading `db/seeds.rb` twice with `SAMPLE=1` gave `6 pickups, 15 devices` both times and `Customer.count == 1`. One latent issue: `Pickup#device_counts` keeps its cached `@device_counts` across `reload`. No controller reloads a pickup that came from `with_device_counts`, so it is unreachable today.

## Fix order (suggested)

BUG-3 + BUG-4 (one-line fixes; a misleading destruction certificate is the worst user-facing outcome) → BUG-2/6 (one server-zone "today" helper) → BUG-1 (demo button can break for good) → BUG-5/7/8 (in-flight guard in `App`) → BUG-9/10.
