# Mini PRD: Pickup Tracker v2 (customer view)

Status: approved for build, 2026-11-01. Contract: `docs/API-v2.md`. Plan: `docs/PLAN-v2.md`.
Inputs: the four audits in `docs/audit/` and the binding FINAL RULING in `docs/audit/RULING-QUESTIONS.md`.

## How sure we are

| Label | Meaning |
|---|---|
| **VERIFIED** | Read on revivn.com on 2026-11-01 (quoted in `docs/audit/matt-domain.md`). |
| **INFERRED** | My reasoning about how ITAD works. Revivn's site doesn't say it. Each one is a question for the interview. |

- VERIFIED: the Revivn app is for managing hardware pickups and tracking progress. Data-bearing devices are sanitized to "DOD and NIST 800-88 standards". Outcomes include resale (customer "earnings"), donation to nonprofits, and recycling. Customers can download asset lists and certificates of destruction.
- INFERRED: devices are tracked per serial number; a device is sanitized before any outcome; a destroyed drive can only be recycled; the certificate lists every serial of a pickup.
- **Per-device certificates are what I'd expect customers need, not a confirmed Revivn feature.** Revivn confirms that certificates of destruction exist, but not their granularity or fields.

## Problem

An IT admin who sends retired hardware to Revivn later has to answer two questions: "Was the data on every device destroyed?" and "What happened to each device?" v1 can't answer either. It counts laptops per batch, shows every company's pickups on one screen, lets the customer click statuses only Revivn can know (including skipping straight to "donated"), hard-deletes records, and has no data-destruction step at all.

## User

An IT admin or IT asset manager at a 200 to 5,000 person customer, signed in to their company account. Secondary readers: their auditor or security team (who receive the certificate) and their ESG lead (who wants outcome counts).

## Jobs to be done

1. "When I have retired hardware, I want to book a pickup and, if I have it, hand over the list of serial numbers, so nothing goes missing between my office and Revivn."
2. "When audit or security asks, I want a certificate that lists every serial number with how and when its data was destroyed, so I can close the ticket in minutes."
3. "When leadership asks what happened to our old hardware, I want counts of resold, donated and recycled devices."

## Decisions (from the FINAL RULING)

| Question | Ruling | What it means in the build |
|---|---|---|
| Q1. How do devices enter? | **C, hybrid** (3-1) | Serial numbers are optional at booking and create `expected` devices. The warehouse can also add devices found at intake, which start `received`. The customer always gives an estimated count. |
| Q2. Pickup status? | **A** (4-0) | Store only `scheduled`, `collected`, `cancelled`. `processing` and `complete` are computed from the devices, so the pickup can never disagree with its devices. |
| Q3. Who changes status? | **A** (4-0) | The customer screen is read-only apart from booking and cancelling. A clearly labelled "Warehouse simulator (demo)" panel drives collect, receive, add device, sanitize and dispose. |

## Scope (v2)

1. **One customer context.** A seeded customer, "Acme Corp", returned by `current_customer`. Every query starts from it. A second customer exists in tests only, to prove its data never leaks.
2. **Book a pickup:** date (today or later), estimated device count (1 to 10,000), optional serial numbers pasted one per line. Status can't be set by the client: every pickup starts `scheduled`.
3. **Per-device lifecycle:** `expected → received → sanitized → resold | donated | recycled`. Forward only, one step at a time. Sanitize records the method (`wipe` or `destroy`) and the time. A destroyed device can only be recycled.
4. **Customer view, read-only:** a pickups list (upcoming first) with derived progress and estimate vs checked-in counts; a detail panel with progress steps and a device table; totals by device outcome.
5. **Certificate of data destruction per pickup:** available only when every device is sanitized (the API answers 409 before that). A printable page using `window.print()` and a print stylesheet. It says it is a demo document, not an official Revivn certificate.
6. **Cancel instead of delete:** the customer can cancel only while `scheduled`. Nothing is ever deleted.
7. **Warehouse simulator (demo):** a separate, labelled panel that calls the warehouse endpoints, so the customer view can be shown updating live.
8. **Realistic seeds,** dated relative to today, built by replaying the real model methods so they obey every rule.
9. **UI quality fixes from the audits:** functional state updates, server error messages shown next to the row that failed, refetch after a failure, long names and serials wrap, focus moves to a sensible place after actions, every button is at least 24px with a visible text label, confirmation before irreversible actions (cancel, sanitize, dispose).

## Non-goals and cut list

| Cut | Why |
|---|---|
| Real login, roles, Devise | Hours of setup that show nothing new. `current_customer` is the seam where a session lookup goes. |
| Site address, contact, time window | Nice-to-have in ecc-product, explicitly left out in matt-domain. Not needed to show the device lifecycle. First thing to add next. |
| Edit or reschedule a pickup | Cancel and rebook covers it while `scheduled`. |
| `data_bearing` flag and device `kind` | Every device is treated as data-bearing. Add the flag when monitors and peripherals come in. |
| PDF gem (Prawn, wicked_pdf) | Browser print already saves a PDF. |
| Refurbish as a tracked step, grading | Internal Revivn steps, not something the customer waits on. |
| Earnings in dollars, fund donation, ESG reports | Real Revivn features, but need data I can't explain the source of. |
| Return kits and shipping | A second intake path; doesn't change the model. |
| Status history / audit log | Next after auth: a real certificate needs who sanitized each device. |
| Notifications, background jobs, pagination, filters, charts, deployment | Ops or scale features; not needed for the three jobs. |
| Serial search box, CSV export | Good nice-to-haves only if everything else is done. Not planned. |
| Frontend test framework (Vitest, Testing Library) | No new npm packages. Pure helpers are tested with Node's built-in `node --test`; UI is checked by lint, build and a written browser checklist. |
| AI feature in the product | Needs a paid key; the JD cares how I work with AI tools, which I tell verbally. |

## Success criteria (demo-verifiable)

- Book a pickup for today with 3 pasted serials and see 3 `expected` device rows in under a minute.
- Every query goes through `current_customer`; another customer's pickup or device answers 404 (controller tests).
- A device can't reach an outcome without `sanitized`, can't move backward or skip, and a destroyed device can only be recycled (model tests).
- Status can't be set on create, a past date is rejected on create, and a future pickup can't be collected (model and controller tests).
- The certificate button stays disabled until every device is sanitized, `GET /pickups/:id/certificate` answers 409 until then, and the printed page lists every serial with method and date.
- Cancel works on a scheduled pickup and answers 422 on any other. `DELETE` no longer exists.
- `GET /pickups` returns upcoming pickups first, so the 200-row limit drops the oldest.
- All backend tests pass, `node --test` passes, and `npm run lint` and `npm run build` are clean.
- I can explain every rule and the customer job it serves.

## Open questions for Revivn (each tests an INFERRED assumption)

1. Is the certificate per pickup, per device, or per reporting period? Which fields do auditors reject when missing?
2. Do customers upload serial numbers before pickup, or does Revivn scan them on arrival? (The hybrid model supports both.)
3. How do you handle a mismatch between the estimated count and what arrives, including listed serials that never show up?
4. Who chooses the outcome: the customer, or Revivn based on condition?

## 90-second demo script

1. "This is Acme Corp's IT admin's view, not Revivn's ops board."
2. Book a pickup for today and paste 3 serials (Job 1). Or use the seeded "today" pickup.
3. In the Warehouse simulator (demo): collect, receive, sanitize one by destroy and the rest by wipe. Point out that the destroyed one is only offered "Recycle", and that the API refuses a resale with a 422 too (the model test proves it).
4. Dispose the rest, watch progress reach Complete, open the certificate and print it (Job 2).
5. Point at the totals by outcome (Job 3), then at this PRD: "I wrote this first, cut auth, addresses and PDFs on purpose, and each rule has a test."
