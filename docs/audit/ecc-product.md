# Product audit: Laptop Pickup Tracker (ecc:product-lens)

Lens: a Revivn Director of Engineering hiring a **Product Engineer, Customer Platform**.
Sources read: `interview-prep/revivn/JD.md`, `interview-prep/revivn/03-company.md`, `README.md`, `frontend/src/App.jsx`, `backend/app/models/pickup.rb`, `backend/app/controllers/pickups_controller.rb`, `backend/db/schema.rb`, `backend/db/seeds.rb`. No code was changed.

**Verdict in one line:** the code is clean and well tested, but the product is aimed at the wrong user. It is a Revivn **ops** screen dressed as a customer screen. For a Customer Platform role, the demo has to be the **customer's** view, and it has to cover the one thing customers buy Revivn for that a moving company can't give them: **per-device proof that their data was destroyed.**

---

## 1. Target user and top 3 jobs-to-be-done

**Target user:** an IT admin or IT asset manager at a 200 to 5,000 person company (the JD lists Instacart, Lyft, Spotify). They have a closet of retired laptops, an auditor or security team asking where every device went, and often an ESG or sustainability lead who wants numbers. They log into the Revivn App a few times per pickup, not every day. Their pain is not "scheduling"; it is **accountability**: "Can I prove that laptop C02XK1 with a former employee's data on it was wiped?"

Revivn's own site says the app is for "manage hardware pickups," "track assets," and "reporting and compliance documentation," with wiping to "DOD and NIST 800-88 standards" (03-company.md, VERIFIED). Certificates and impact reports per device are INFERRED in 03-company.md, so in the interview present them as "what I'd expect customers ask for," not as facts about Revivn's product.

| # | Job-to-be-done (customer's words) | What "done" looks like |
|---|---|---|
| 1 | "When I have retired laptops, I want to book a pickup and hand over the list of serial numbers, so that nothing goes missing between my office and Revivn." | Pickup booked with site address, contact and date; every serial is on record before the truck arrives. |
| 2 | "When audit or security asks, I want a data-destruction certificate that lists every serial number, so that I can close the compliance ticket in minutes." | One click from a pickup to a printable certificate: serial, wipe method, date, per device. |
| 3 | "When leadership or ESG asks what happened to our old hardware, I want a per-device outcome summary (resold, donated, recycled), so that I can report value and impact." | Counts by outcome per pickup and in total; donated devices tie to Revivn's Tech Access story. |

---

## 2. What's wrong with the current flow

**Whose view is it?** Revivn ops', by accident. Evidence in `App.jsx`:

| Problem | Evidence | Why a hiring manager notices |
|---|---|---|
| **Customer types their own company name.** | Form field `company`; "All pickups" table lists 10 different companies (`seeds.rb`). | A customer sees only their own account. A list of every company is an internal ops board, and showing it to a customer would be a data leak. |
| **Customer advances the status.** | The stepper buttons call `changeStatus` (scheduled → picked_up → refurbished → donated). | Customers don't mark their laptops "refurbished." Revivn does. In a customer view, status is read-only and comes from the warehouse. |
| **Customer can delete any pickup, at any stage.** | `deletePickup` on every row, `destroy` in the controller with no state check. | Deleting a "donated" batch destroys the chain-of-custody record the customer needs for audit. At most a customer should **cancel** a pickup that is still `scheduled`. |
| **Unit of tracking is the batch, not the device.** | Schema has `device_count` (an integer) and no devices table. | ITAD compliance is per serial number. "12 laptops" can't answer "where is serial C02XK1?" This is the biggest gap. |
| **No data-destruction step.** | `STATUSES = scheduled, picked_up, refurbished, donated`. | Wiping is the compliance core of the product (NIST 800-88 per Revivn's site). The README's own "What I'd do next" lists it, which tells the interviewer you knew it mattered and shipped without it. |
| **Lifecycle is a straight line, but outcomes branch.** | `refurbished` must come before `donated`; no `resold` or `recycled`. | Real devices end in one of several outcomes: resold, donated, or recycled (if broken). A forced linear chain is the wrong model. |
| **No pickup logistics.** | No address, contact, or time window. | You can't actually send a truck from this form. |
| **Summary numbers serve ops, not the customer.** | "Devices by stage" across all companies. | A customer wants "my devices: 40 wiped, 30 resold, 8 donated, 2 recycled" and "certificates ready." |

What's right and worth keeping: Rails model validations with tests (27), forward-only status rule (it becomes the chain-of-custody rule on devices), 422 errors shown under each field, loading/empty/error states, the Vite proxy, and the honest README. Those are all strong signals for the "Engineering & Delivery" half of the JD.

---

## 3. v2 list ranked by interview impact per hour

Score = interview impact (1 to 5) / hours. Total for must-haves is about 7.5 hours, which leaves room for testing and rehearsal inside one day.

### Must-have (build these, in this order)

| Rank | Change | Impact | Hours | Why it matters to the interviewer |
|---|---|---|---|---|
| 1 | **Reframe the screen as one customer account.** Seed one `Account` ("Acme Corp"); add `current_account` in `ApplicationController` that returns it; scope every query with `current_account.pickups`. Remove the company field. Header says "Acme Corp: your pickups." | 5 | 0.75 | Shows you know whose platform this is, and shows the tenant-scoping pattern a real login would plug into. |
| 2 | **Add serial numbers at booking.** New `devices` table (`pickup_id`, `serial_number`, `model`, `status`). The booking form gets a textarea "Paste serial numbers, one per line"; `device_count` is derived from it. Validate unique serial per account, reject blank lines. | 5 | 2 | Moves tracking from batch to device. This is the line that makes the demo look like ITAD and not a to-do app. |
| 3 | **Make status read-only for the customer; move "advance" to a clearly labeled demo control.** Pickup row shows a status timeline with dates. A separate footer block "Demo only: simulate Revivn warehouse" advances devices so you can show the flow live. | 4 | 1 | Correct split between customer and ops actions. You can say: "In production this is the warehouse app writing to the same API." |
| 4 | **Device lifecycle with a wipe step and branching outcome.** Device statuses: `expected → received → wiped → resold / donated / recycled`. Forward-only rule moves from Pickup to Device (reuse your existing validation). Store `wiped_at` and `wipe_method` ("NIST 800-88 Purge"). Pickup status is derived: scheduled / in processing / complete. | 5 | 1.5 | Puts data destruction at the center, as Revivn does, and models outcomes correctly. |
| 5 | **Data-destruction certificate per pickup.** Button appears when every device is wiped. Opens a printable page (a React view + `window.print()` and a print stylesheet, no PDF gem) listing company, pickup date, and each serial with wipe method and date. | 5 | 1.25 | This is Job #2 and the compliance deliverable customers ask support for most often. Highest impact moment in the demo. |
| 6 | **Cancel instead of delete.** Allow cancel only while `scheduled` (model validation + test); no delete after pickup. | 3 | 0.5 | Small, but it shows you think about audit trails. Good line-by-line talking point. |
| 7 | **Ship the v2 PRD (section 4) in the repo** as `docs/PRD-v2.md` and link it from the README. | 4 | 0.5 | The JD says "you'll be writing your own PRDs and specs." Showing the PRD that drove the build is direct proof. |

### Nice-to-have (only if must-haves are done and tested)

| Change | Impact | Hours | Note |
|---|---|---|---|
| Serial search box: "Where is C02XK1?" returns pickup, status, outcome. | 4 | 0.75 | Great 10-second demo moment; it is a one-line `where` plus an input. |
| Impact summary card: devices resold / donated / recycled, with "donated devices went to Tech Access" copy. | 3 | 0.75 | Job #3. Leave out dollar resale values and kg estimates unless you can explain the source. |
| Pickup logistics fields: site address, contact email, time window. | 3 | 0.5 | Realism; easy validations. |
| CSV export of devices for a pickup (Rails `send_data` with stdlib `CSV`). | 3 | 0.75 | IT admins live in spreadsheets; no new gem. |
| A "support ticket" story: write one fake P2 in the README ("customer says certificate is missing serials") and the commit that fixed it. | 3 | 0.5 | Maps to the JD's P2/P3 support half. Only if it's a real bug you hit. |

### Cut (say why if asked)

| Cut | Reason |
|---|---|
| Real authentication / Devise | Hours of setup that shows nothing new; the `current_account` seam explains where it plugs in. |
| PDF generation gem (Prawn, wicked_pdf) | Browser print gives a PDF for free. |
| Email notifications, background jobs | Not core to the three jobs; adds infrastructure to explain. |
| AI feature inside the app (for example LLM parsing of messy asset sheets) | Needs a paid API key, and the JD wants to hear **how you work** with AI tools, not an AI feature. Tell that story verbally: how Claude Code was used to build, test and review this. |
| Charts, pagination, filters, multi-company admin board | Ops or scale features; not what the customer platform demo needs. |
| Deployment | Nice to have a link, but local demo plus screen share is enough for a one-day budget. |
| Frontend test suite | Keep backend Minitest coverage for the new rules (serial uniqueness, forward-only device status, cancel only while scheduled, certificate only when all wiped). |

---

## 4. Mini PRD: Pickup Tracker v2 (customer view)

**Problem.** An IT admin who sends retired laptops to Revivn has to answer two questions later: "Was the data on every device destroyed?" and "What happened to each device?" Today's tracker counts laptops per batch, shows every company's pickups on one screen, and lets the customer edit statuses that only Revivn can know. It can't produce proof for a single serial number.

**User.** IT admin or IT asset manager at a mid-size or enterprise customer, signed in to their company account. Secondary reader: their auditor or ESG lead, who receives the certificate or summary.

**Scope (v2).**
1. Single customer account context (`current_account`); all data scoped to it.
2. Book a pickup: date plus a pasted list of serial numbers (one per line); device count is derived.
3. Per-device lifecycle: expected → received → wiped → resold / donated / recycled; forward-only; wipe method and date stored.
4. Customer sees status read-only: pickup timeline plus per-device table.
5. Data-destruction certificate per pickup, available only when every device is wiped; printable from the browser.
6. Customer can cancel a pickup only while it is scheduled; no deletion after pickup.
7. A clearly labeled demo-only control that simulates Revivn warehouse updates.

**Non-goals.** Real login and roles; Revivn's internal ops app; notifications; resale pricing; PDF libraries; deployment; any AI feature in the product.

**Success criteria (demo-verifiable).**
- From a blank form, book a 5-serial pickup and see 5 device rows in under 1 minute.
- Every query goes through `current_account`; a seeded second account's pickups never appear (covered by a controller test).
- A device can't move backward or skip from `expected` to an outcome without `wiped` (model tests).
- The certificate button is hidden until all devices are wiped; the printed page lists every serial with wipe method and date.
- Cancel works on a scheduled pickup and returns 422 on any later one (tests).
- All backend tests pass; each new rule has at least one test.
- In the interview, you can explain every model rule and why it exists, pointing to the customer job it serves.

**Open questions to bring to the customer team (shows discovery instinct).** Do customers upload serials before pickup, or does Revivn scan them on arrival? Which certificate fields do auditors actually reject when missing? Is the certificate per pickup or per device? These are the questions you'd ask Revivn's customer team in week one, and saying so in the interview maps straight to the JD's "Discovery & Product Ownership" section.

---

## Demo script in 90 seconds (suggested)

1. "This is the customer's view: Acme Corp's IT admin." (Job framing.)
2. Book a pickup and paste 5 serials. (Job 1.)
3. Use the demo control to simulate Revivn receiving and wiping the devices; point out that the customer can't edit statuses.
4. Open the certificate and print it. (Job 2.)
5. Show the PRD and say: "I wrote this first, cut auth and PDFs on purpose, and here's the test for each rule."
