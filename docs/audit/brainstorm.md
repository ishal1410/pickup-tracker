# Brainstorm: what to add before the Revivn screens

Date: 2026-11-02. Method: `superpowers:brainstorming`, diverge then converge. No code was changed for this document.

Inputs read: `README.md`, `docs/PRD-v2.md`, `docs/decisions.md`, `frontend/src/App.jsx`, every file in `backend/app/`, `backend/config/routes.rb`, `backend/db/schema.rb`, `backend/Gemfile.lock`, and `interview-prep/revivn/JD.md` plus `03-company.md`.

Revivn facts used here are the ones already marked VERIFIED in `PRD-v2.md` and `03-company.md`, plus the brief's list from revivn.com: managing pickups, asset tracking, compliance documents and certificates of destruction, resale earnings, environmental impact reports, return kits for remote employees, and an API for IT stacks. Anything else is labelled INFERRED.

## Clarifying questions (answered from context, not asked)

| Question | Answer | Source |
|---|---|---|
| Who is the audience tomorrow? | A recruiter screen (15 min, product story) and then a dev round (Rails + React, line by line). | `03-company.md`, brief |
| What counts as success? | Each addition is demoable in under 30 seconds, maps to a JD line, and every line can be explained. | JD "walk us through real examples", plan rule |
| Hard limits? | No new gems or npm packages. No invented Revivn features. Roughly one evening of build time. | brief, PRD cut list |
| Rails or React first? | Rails. The role names Rails first, and the current app's Rails depth is its strongest asset. | JD, README |
| Can the existing rules move? | Yes, if the change is a recorded decision (new ADR), the way v2 was built. | `decisions.md` |

## 1. What's missing at a 10-second glance

An IT admin or a Revivn engineer opening the portal would look for these and not find them:

1. **"Where is serial C02XK1?"** There is no way to find one device without opening pickups one by one. The device is the unit of the whole model (ADR-001), but it has no index route: `resources :devices, only: []`.
2. **An asset list to download.** `PRD-v2.md` line 13 marks this VERIFIED ("Customers can download asset lists"), yet the app has no export. This is the biggest gap between the demo and a confirmed Revivn feature.
3. **When each step happened.** The device row keeps only `sanitized_at`. There's no received time and no history, so "what happened to this laptop and when" has half an answer. The README and PRD both name the audit log as the next item.
4. **A way out for a serial that never shows up.** This one is a real bug in my code. `Pickup#certificate_available?` needs `counts["expected"].zero?`, and `expected` can only move to `received`. A listed serial that never reaches the warehouse therefore blocks the certificate forever. Sample pickup 2 (`DemoData`, serial `R9WT40ABCDE`) is in exactly that state. PRD open question 3 asks about it, but the code has no answer.
5. **Anything about remote employees, earnings or impact.** These are on Revivn's site and absent here. They were cut on purpose in the PRD ("need data I can't explain the source of"), and that reasoning still holds for earnings and impact.
6. **No integration story.** Revivn sells an API for IT stacks. The API exists and is documented (`docs/API-v2.md`), but nothing in the UI says so.

## 2. Ten candidates (diverge)

| # | Candidate | What it would be |
|---|---|---|
| A | **Serial search** | `GET /devices?q=C02` scoped to `current_customer.devices`, prefix match, plus a search box that opens the matching pickup. |
| B | **CSV asset export** | `GET /devices.csv` (all devices) or `/pickups/:id/devices.csv`: serial, model, pickup date, status, method, sanitized at. |
| C | **Per-device audit timeline** | A `device_events` table written inside `ForwardOnly#move_to`, shown as a timeline under each device row and as per-device dates on the certificate. |
| D | **P2 support fix: "certificate stuck"** | Ticket, failing test, fix: a warehouse `mark_not_received` step (`expected -> not_received`, terminal), with the certificate listing such devices as "not received, no destruction claimed". |
| E | **Remote-employee return kit** | Book a kit request (employee name, email, address), with status kit sent, in transit, received, which then joins a pickup's devices. |
| F | **Earnings report** | A resale value per resold device and a total. |
| G | **Environmental impact report** | CO2 or e-waste avoided, computed from outcome counts. |
| H | **API key / integrations page** | Issue a token, show curl examples against the existing endpoints. |
| I | **Email notification stub** | ActionMailer: "Your certificate is ready" when the last device is sanitized, previewed in development. |
| J | **Mismatch flag (estimate vs arrived)** | A pill when checked-in count differs from the estimate, or a listed serial is still expected after N days. |

Not shortlisted: booking address and contact (useful, but shows nothing new about the domain), and an AI feature (needs a paid key and breaks the zero-budget rule).

## 3. Scoring

Scale 1 to 5. Honesty risk: 1 is safe, 5 means it would show invented Revivn data or behaviour. Hours are for build plus tests plus a doc line, at the pace v2 was built.

| # | Candidate | Interview impact | Rails showcase | Honesty risk | Hours | Notes |
|---|---|---|---|---|---|---|
| A | Serial search | 4 | 4 | 1 | 1.0 | Tenancy scope, `sanitize_sql_like`, the unique index on `serial_number` makes prefix lookup cheap. |
| B | CSV export | 5 | 4 | 1 | 1.0 | Closes a VERIFIED gap. `respond_to` with `format.csv`, `send_data`. See the CSV caveat below. |
| C | Audit timeline | 5 | 5 | 1 | 2.5 | Migration, association, write inside the existing lock, certificate gets real dates. Answers "who did what when" for an auditor. |
| D | P2 fix: stuck certificate | 5 | 4 | 1 | 1.5 | A bug that exists in my code today. Direct match to the JD's "P2/P3 support fixes". Needs one new status, a check-constraint change and an ADR. |
| E | Return kit | 3 | 3 | 3 | 4+ | VERIFIED feature, but its real flow (who ships, what tracking) is unknown, so most of the UI would be guessed. A second intake path that doesn't change the model (PRD cut list). |
| F | Earnings | 3 | 2 | 5 | 1.5 | Any dollar figure would be invented. The PRD cut it for that reason. |
| G | Impact report | 2 | 2 | 5 | 1.5 | Needs per-device CO2 factors I can't source. Outcome counts already exist in the summary. |
| H | API key page | 3 | 3 | 4 | 3 | Without auth (ADR-007) the key would do nothing. A page that implies security that isn't there is worse than none. |
| I | Email stub | 2 | 3 | 2 | 1.5 | `action_mailer/railtie` is commented out in `config/application.rb`; turning it on is fine, but there is nothing to see in a screen share without a preview tool. |
| J | Mismatch flag | 3 | 2 | 1 | 0.5 | Mostly derived from data already sent. Becomes a nice extra on top of D. |

**CSV caveat (checked).** In Ruby 3.4, `csv` is a bundled gem, not a default one, and it is not in `backend/Gemfile.lock`. Under Bundler, `require "csv"` would fail unless the gem is added, which breaks the no-new-gems rule. So the CSV has to be written by hand: about six lines that quote every field, double inner quotes, and prefix a `'` to any cell starting with `=`, `+`, `-` or `@` (spreadsheet formula injection). That is easy to explain and makes a good talking point. The other option is building the file in the browser from JSON with a `Blob`, tested in `lib.test.js`. The Rails version is the better showcase for this role.

## 4. Converge: the top 3

Selection rule: high interview impact, low honesty risk, Rails first, and all three together fit in about five hours. A and B share one endpoint, so they ship as one item.

### Top 1. Asset list: serial search and CSV export (A + B), about 2 hours

**Rails.** Add `index` to `resources :devices` and point it at `DevicesController#index`. The query starts from `current_customer.devices.includes(:pickup)` so tenancy holds. An optional `q` param filters with `where("serial_number LIKE ?", "#{Device.sanitize_sql_like(q.strip.upcase)}%")`, which uses the existing unique index. Results are ordered by serial and capped at 200, with the same ponytail comment as `PickupsController#index`. `respond_to` serves two formats from that one query. `format.json` returns each device's `as_json` merged with `pickup_date` and the pickup's `progress`. `format.csv` calls `send_data` with `type: "text/csv"` and a dated filename, built by a small `Device.to_csv(devices)` class method that does the hand-written quoting above, with the formula-injection guard. Tests: a Globex device never appears in either format, a prefix query matches and a substring query doesn't, the CSV has a header row, and a serial starting with `=` comes out escaped. Add `/devices` to the Vite proxy list. **React.** A search box above "Your pickups". Results list serial, model, status and pickup date, and clicking a result calls the existing `openPickup(pickup_id)`. A plain `<a href="/devices.csv" download>` labelled "Download asset list" needs no JavaScript. **Why it wins:** it closes the one VERIFIED Revivn feature the demo lacks, and "where is this serial?" is the first question an IT admin asks.

### Top 2. P2 support fix: "my certificate never unlocks" (D), about 1.5 hours

Write it as a real ticket in `docs/support/P2-stuck-certificate.md`: the customer report ("pickup collected on the 24th, certificate button still greyed out"), how I reproduced it (sample pickup 2, serial `R9WT40ABCDE` stays `expected`), the root cause (`certificate_available?` needs zero `expected`, and `expected` has no exit except `received`), the fix, and the test. **Rails.** Add `not_received` to `Device::STATUSES` and `TRANSITIONS` (`"expected" => %w[received not_received]`), so `ForwardOnly` covers it with no new guard code. Add `Device#mark_not_received` and `POST /devices/:id/mark_not_received` (warehouse simulator only, pickup must be collected, same `render_result`). A migration replaces two check constraints: `devices_status_allowed` gains `not_received`, and `devices_sanitized_fields` adds `not_received` to its first branch. That second change matters because the constraint's `CASE` currently puts every status other than `expected` and `received` in the "must have a method and date" branch, and a not-received device has neither. `certificate_available?` stays as it is (it already ignores statuses other than expected and received), and `progress` counts `not_received` as finished. The certificate JSON adds a `not_received` list, and the printed page shows those serials under "Not received by Revivn. No data destruction is claimed for these devices." Failing test first: a collected pickup with one sanitized and one never-arrived device answers 409 today and 200 after the fix, and the not-received serial appears in the separate list, never in the destroyed one. Record it as ADR-009. **React.** A "Mark not received" button on expected rows in `WarehousePanel`, with the existing confirm, plus a neutral grey `tone-not_received` pill. **Why it wins:** the JD lists P2/P3 support fixes as part of the job, and this is a real bug found in my own code, carried from report to shipped fix. It also answers PRD open question 3 instead of leaving it open.

### Top 3. Per-device audit timeline (C), about 2.5 hours

**Rails.** Add a migration for `device_events`: `device_id` (foreign key, not null, indexed), `from_status`, `to_status`, `created_at`, plus a check constraint that `to_status` is a known status. Add `Device has_many :events` (ordered by id) and a `DeviceEvent` model with no update path. The write goes in one place: `ForwardOnly#move_to`, inside the existing `with_lock` block, right after a successful `update`, so every action (receive, sanitize, dispose, cancel, collect, and `mark_not_received` from Top 2) records itself with no change to any caller. `Pickup` gets the same treatment for its own transitions through a `pickup_events` table, or the first version covers devices only, which is enough for the certificate. Creation writes a first event (`nil -> expected` or `nil -> received`) in an `after_create`. `as_json_with_devices` includes each device's events, loaded with `includes(devices: :events)` to avoid N+1. The certificate adds `received_at` per device, taken from the events. Tests: a full receive, sanitize, dispose run leaves three events in order, a refused move writes nothing (it rolls back with the lock), and `DemoData` still builds. Note in ADR-010 that there is no `actor` column yet, because without auth (ADR-007) every actor would be "Acme Corp", which would be a false record. That column arrives with login. **React.** An expandable row in `PickupDetail`'s device table showing "Received Nov 1, 2:05 pm, Sanitized (wipe) Nov 1, 2:40 pm, Resold Nov 2". **Why it wins:** it is the most Rails-heavy item (migration, constraint, concern, eager loading), it turns the certificate from a status snapshot into chain of custody, and it is the item both the README and the PRD already name as next, so the build follows my own written plan.

### Order and time box

Build Top 2 first (smallest, and its story works in the recruiter screen even if nothing else ships), then Top 1, then Top 3. Total is about 6 hours. If time runs out, Top 3 drops to a written spec, which is still a fair thing to show for a role that writes PRDs.

### Explicitly not building, and what to say if asked

- **Return kits:** "It's on Revivn's site, but I don't know the real flow: who ships the box, what tracking you use. I'd rather ask your customer team than guess. In my model it's a second way devices enter a pickup, like intake."
- **Earnings and impact reports:** "Both are real Revivn features, but every number would be made up. Outcome counts are already in the summary; dollars and CO2 need your pricing and factors."
- **API keys:** "The API exists and is documented, but without auth a key page would suggest security that isn't there. Login comes first (ADR-007)."

## Open risks to check while building

1. **Time zones, unverified.** `config.time_zone` is Eastern, and `pickup_date_not_in_past` uses `Date.current`, while the browser's minimum date is the local day. A user in Hawaii booking "today" late in the evening may get "can't be in the past". The v1 QA checked display only (`gstack-qa.md` line 51), not booking. Reproduce it before claiming it. If it's real, it's a second P2 story.
2. Changing the `devices_sanitized_fields` constraint (Top 2) means a migration on SQLite, which rebuilds the table. Run the full test suite and `SAMPLE=1 bin/rails db:seed` afterwards.
3. Every new line has to stay explainable, with no metaprogramming. The CSV writer and the event write are the two places to keep deliberately plain.
