# QA Report v2: Pickup Tracker (gstack /qa, test, fix, re-verify)

- **Date:** 2026-11-02 (browser clock: Mon Nov 02 2026, Eastern)
- **Target:** http://localhost:5173 (Vite + React 19) proxying `/customer`, `/pickups`, `/devices` to Rails 8.1 on :3000
- **Driver:** Playwright Chromium, run from Node with gstack's bundled Playwright, timezone `America/New_York`. I tried gstack `$B` first and dropped it because it can't scope selectors to a table row. Aside isn't available on Windows.
- **Spec:** `docs/API-v2.md` (binding), `docs/PRD-v2.md` (90-second demo script), `docs/PLAN-v2.md`
- **Tier:** Standard (fix critical, high and medium; low only when it costs one line)
- **Test data:** serials prefixed `QA-` (`QA-D1-*`, `QA-DUP-*`, `QA-INTAKE-01`, `QA-KB*`, ...). I re-seeded with `ruby bin/rails db:seed` at the end ("Seeded Acme Corp: 6 pickups, 15 devices"). `GET /pickups` now contains 0 `QA` strings.
- **Git:** the project isn't a git repository, so I made no commits. Each fix below lists the files it changed.
- **Screenshots:** `docs/audit/shots-v2/` (26 files)

## Health score: 84 before, 95 after

| Category | Weight | Before | After | Notes |
|---|---|---|---|---|
| Console | 15% | 70 | 70 | No JS exceptions and no React warnings in any run. Chrome logs `Failed to load resource: 422/500/404/ERR_FAILED` for every failed request. Those come from the browser's network layer and app code can't silence them (see "Not fixed"). |
| Links | 10% | 100 | 100 | Single-page app |
| Visual | 10% | 85 | 100 | ISSUE-002 |
| Functional | 20% | 85 | 100 | ISSUE-001 |
| UX | 15% | 82 | 100 | ISSUE-003, 004, 006 |
| Performance | 10% | not scored | not scored | The full demo took 4.5 s of scripted clicks against the local API. I took no other measurements. |
| Content | 5% | 85 | 100 | ISSUE-005 |
| Accessibility | 15% | 86 | 97 | ISSUE-003, 006. The remaining 3 points are the cancelled-pickup copy nit (see "Not fixed"). |

Score = weighted sum / 0.90 tested weight. Before: 75.45 / 0.9 = 83.8, rounded to **84**. After: 85.5 / 0.9 = **95**.

> QA found 6 issues (0 critical, 0 high, 4 medium, 2 low) and fixed all 6. Health score 84 → 95.

## 90-second demo script: passes, before and after the fixes

| Step | Result | Evidence |
|---|---|---|
| 2. Book today, 3 serials pasted as `qa-d1-01`, `QA-D1-02` and `  QA-D1-03  ` | 201. Notice reads "Pickup booked for Nov 2, 2026 with 3 serial numbers." 3 `Expected` rows, all stored uppercased and trimmed. Focus moves to the detail heading. | shots-v2/02-booked-3-serials.png |
| 3. Collect, receive ×3, sanitize 1 by destroy and 2 by wipe | Every step updates the list, panel and totals. The destroyed row offers only `[Recycle]`; the wiped rows offer `[Resell, Donate, Recycle]`. Confirm texts are clear, e.g. "Destroy the drive in QA-D1-01? It can then only be recycled." | shots-v2/03-sanitized-destroy-only-recycle.png |
| 3. The API refuses a resale of a destroyed drive | `POST /devices/:id/dispose {"outcome":"resold"}` → **422** `{"status":["can only be recycled after the drive is destroyed"]}` | (fetch log) |
| 4. Dispose the rest → Complete → certificate → print | Progress reaches `Complete`. The certificate lists all 3 serials with method, time and outcome, plus the demo disclaimer. Print media shows only the certificate. | shots-v2/04-complete-certificate.png, 05-print-preview.png, 60-print-after.png |
| 5. Totals by outcome | Totals update live (for example, Resold 3 → 4, Donated 1 → 2, Recycled 2 → 3) | (text log) |
| Same script on the seeded "today" pickup, after the fixes | Passes, 0 JS errors | shots-v2/issue-001-after.png |

## Other flows tested

| Flow | Result |
|---|---|
| Blank submit | "Pickup date can't be blank", "Estimated device count is not a number" (focus: ISSUE-003) |
| Past date (Nov 1) | "Pickup date can't be in the past", focus on date |
| 0, 10001 and 2.5 devices | "must be greater than 0", "must be less than or equal to 10000", "must be an integer" |
| Duplicates, lowercase, blank lines, already registered | `qa-dup-1` + `QA-DUP-1` + blank lines + `QA-D1-01` → "QA-DUP-1 is listed more than once" and "QA-D1-01 is already registered". Focus moves to the textarea. Hint says "(3 listed)" because blank lines aren't counted. (shots-v2/11-dupes-registered.png) |
| 51+ character serial | "... is longer than 50 characters" (wrapping: ISSUE-002) |
| 50-character serial + lowercase + blank lines | Booked; serials stored as `QA-LOW-1` and the 50-character serial (shots-v2/13-booked-lowercase-50char.png) |
| Booking without serials | "Pickup booked for Nov 3, 2026." Panel says no devices yet (copy: ISSUE-004) |
| Double submit (800 ms delayed POST, plus Enter and a second click) | Button shows "Booking…" and is disabled. **1** POST sent. |
| Collect a future pickup | "Pickup date is in the future, so the pickup can't be collected yet" next to the button (shots-v2/20-collect-future-error.png) |
| Cancel: dismiss the confirm, then accept it | Dismiss: nothing changes. Accept: `Cancelled`, the Cancel button is gone, the simulator says "This pickup was cancelled. Nothing to simulate.", focus moves to the detail heading (shots-v2/21-cancelled.png). Cancel shows only while `scheduled`. |
| Add an unexpected device: blank, duplicate, valid with a 90-character model | "Serial number can't be blank" and "Serial number has already been taken", with the typed value kept. A valid entry is added as `Received`, the inputs clear, focus returns to the serial input, progress becomes Processing (shots-v2/22-added-device.png) |
| Stale screen (device received in a second tab, then Receive clicked) | Error "Status can't go from received to received" next to the row. The row refetches and now offers the sanitize buttons. Focus stays on the row (shots-v2/24-stale-refetch.png) |
| Load failure + Retry | Banner with a Retry button, booking paused, figures show "—" instead of zeros. Retry loads 10 rows (shots-v2/30-load-fail.png) |
| Booking network failure | Error shown and values kept (wording: ISSUE-005) (shots-v2/31-post-fail.png) |
| Keyboard only | Tab order: date → count → serials → Book → each View button. Visible 2px focus ring. Booking and Cancel both work from the keyboard. Focus lands on the detail heading after booking (shots-v2/40-keyboard-focus.png) |
| 375px mobile | `scrollWidth` 375 on the list and detail views. No element overflows. No button is under 24px (shots-v2/50-mobile-375.png, 51-mobile-375-detail.png). Long-serial error: ISSUE-002 |
| API probes (curl) | `{}` → 400. Unknown or invalid date → 422 "can't be blank". `status: "collected"` is ignored on create. `DELETE /pickups/1` → 404. Other customers' and unknown ids → 404 JSON. |

## Issues and fixes

### ISSUE-001 (Medium, Functional): an open certificate goes stale after a warehouse step
**Repro:** sanitize every device, open the certificate, then click Recycle in the simulator. The pickup panel says `Recycled`, but the certificate still says **"Awaiting outcome"** until you close and reopen it. This happens easily if the demo opens the certificate before disposing.
**Evidence:** before: `cert after recycle ['QA-INTAKE-01 ... Drive destroyed ... Awaiting outcome']` (shots-v2/issue-001-before.png). After: `cert after ['Recycled','Resold','Donated']` and `focus after dispose (cert open): warehouse-heading` (shots-v2/issue-001-after.png).
**Fix:** `App.jsx` passes a `version` prop (the pickup's `device_counts`) to `<Certificate>`. `Certificate.jsx` refetches when `version` changes and moves focus to its heading only on the first load, so a refetch can't pull focus away from the simulator.
**Files:** `frontend/src/App.jsx`, `frontend/src/Certificate.jsx`. **Status:** verified.

### ISSUE-002 (Medium, Visual): a long serial in a booking error overflows the card and the page
**Repro:** paste a 62-character serial with no spaces and click Book. The error line runs past the card edge. At 375px the page scrolls sideways (`scrollWidth` **500**).
**Evidence:** shots-v2/issue-002-before.png. After: the error ends at x=474, inside the form's right edge at 498. Mobile `scrollWidth` is **375** (shots-v2/issue-002-after.png, issue-002-mobile-after.png).
**Fix:** add `.field-error, .row-error` to the existing `overflow-wrap: anywhere` rule.
**Files:** `frontend/src/index.css` (1 line). **Status:** verified.

### ISSUE-003 (Medium, Accessibility/UX): a blank submit focuses the second field, not the first
**Repro:** click Book with an empty form. Focus jumps to "Estimated number of devices", skipping the date error above it. The cause: the server's error keys follow Rails validation order, not form order.
**Evidence:** before: `blank: ... focus estimated_device_count` (shots-v2/issue-003-before.png). After: `blank focus: pickup_date`.
**Fix:** `BookingForm.jsx` picks the first failing field from the fixed form order `['pickup_date', 'estimated_device_count', 'serial_numbers']`.
**Files:** `frontend/src/BookingForm.jsx`. **Status:** verified.

### ISSUE-004 (Low, Content): "0 of 0 sanitized" and a certificate button on cancelled pickups
**Repro:** open a pickup with no devices: it says "0 checked in, 0 of 0 sanitized" and "ready once every device is sanitized (0 of 0 so far)". A cancelled pickup still shows a disabled "View certificate" button and that hint, although it can never get a certificate.
**Fix:** with no devices, the summary reads only "You estimated N." and the hint reads "The certificate is ready once devices are checked in and every one is sanitized." Cancelled pickups hide the certificate button and hint. (My first version also added "No devices listed yet." to the summary. That repeated the empty-table message, so I removed it before the final check.)
**Evidence (after):** `Oct 31 | You estimated 8. / The certificate is ready once devices are checked in and every one is sanitized.` and `Nov 3 (cancelled) | Cancelled / You estimated 4. / No devices listed yet...` (shots-v2/issue-004-after.png)
**Files:** `frontend/src/PickupDetail.jsx`. **Status:** verified.

### ISSUE-005 (Medium, Content): raw browser errors shown to the customer
**Repro:** cut the network during any action and the UI shows **"Failed to fetch"** (or "Couldn't book the pickup. Failed to fetch"). A 5xx with an HTML body shows **"Request failed (500)"**.
**Evidence:** shots-v2/issue-005-before.png. After: "The server didn't respond. Check your connection and try again." and "Something went wrong on the server (500). Please try again." (shots-v2/issue-005-after.png)
**Fix:** `api()` in `lib.js` catches the `fetch` rejection and throws a plain-English error with `status: 0`. A 5xx without a JSON `{error}` gets a readable fallback. 4xx messages are unchanged, so the existing 404 test still passes.
**Regression tests (written first, failing, then passing):** 2 new tests in `frontend/src/lib.test.js`: "api turns a network failure into a plain sentence" and "api explains a 5xx without a JSON body".
**Files:** `frontend/src/lib.js`, `frontend/src/lib.test.js`. **Status:** verified.

### ISSUE-006 (Low, Accessibility): focus falls to `<body>` when a viewed pickup returns 404
**Repro:** View a pickup that the server answers with 404. The row is removed and "That pickup no longer exists." shows, but focus drops to `BODY`.
**Fix:** `forget()` focuses the "Your pickups" heading (now `tabIndex={-1}`).
**Evidence:** after: `404 focus: pickups-heading`.
**Files:** `frontend/src/App.jsx`. **Status:** verified.

## Not fixed (deliberately)

- **Chrome's "Failed to load resource: 422" console lines.** Chrome logs these itself for every non-2xx response. App code can't suppress them without client-side validation that duplicates the server's rules. The server is the source of truth, so I left this. There are no JS errors.
- **Backend:** I found no bugs, so I made no backend changes and wrote no new backend tests. Small notes that aren't worth a change: a JSON float like `1e3` for `estimated_device_count` gets "must be an integer" (the form always sends a string); an impossible date like `2026-13-45` gets "can't be blank"; a non-array `serial_numbers` is silently dropped by strong params. The UI can't send any of these.
- **Cancelled pickup with no devices** still says "Revivn records each serial number when the devices arrive". The wording is slightly off for a cancelled pickup, but harmless.
- **Several pickups on the same date look identical in the list** (only the date differs between rows). Seed data has one pickup per date, so the demo isn't affected.

## Final verification output

`frontend/`:
```
> npm run lint
> eslint .
(no output: 0 problems)

> npm run build
dist/index.html                 1.03 kB │ gzip:  0.54 kB
dist/assets/index-Ce0W68r8.css  9.24 kB │ gzip:  2.97 kB
dist/assets/index-CN6qqib9.js 244.60 kB │ gzip: 75.40 kB
✓ built in 1.05s

> node --test src/lib.test.js
ℹ tests 12
ℹ pass 12
ℹ fail 0
```

`backend/`:
```
> ruby bin/rails test
83 runs, 216 assertions, 0 failures, 0 errors, 0 skips

> ruby bin/rails db:seed
Seeded Acme Corp: 6 pickups, 15 devices.
```

## Files changed

- `frontend/src/App.jsx`: certificate `version` prop (001); focus after 404 and `tabIndex` on the pickups heading (006)
- `frontend/src/Certificate.jsx`: refetch on `version`; focus only on first load (001)
- `frontend/src/index.css`: wrap `.field-error` and `.row-error` (002)
- `frontend/src/BookingForm.jsx`: focus the first failing field in form order (003)
- `frontend/src/PickupDetail.jsx`: copy for pickups with no devices; no certificate on cancelled pickups (004)
- `frontend/src/lib.js`: readable network and 5xx errors (005)
- `frontend/src/lib.test.js`: 2 regression tests (005)
