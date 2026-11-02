# Wrong-flow check: Pickup Tracker v2

Date: 2026-11-02. Report-only. No code was changed.
Target: http://localhost:5173 (Vite) with Rails on :3000. Driver: Playwright (headless Chromium) from gstack's node_modules, plus `curl` against the API to try out-of-order moves.
Read first: `docs/audit/matt-domain.md`, `docs/PRD-v2.md`, `README.md`, `docs/API-v2.md`.
Personas: (a) a recruiter seeing it for the first time, (b) an enterprise IT admin (the customer), (c) a Revivn ops person using the simulator.
Screenshots: `docs/audit/shots-flow/`.
Cleanup: ended with `POST /demo/reset {"sample":false}`, which returned `pickups_count: 0`, so Acme is empty.

Note: during the run, five "Nov 10, 2026, est. 2" scheduled pickups appeared that I did not create (visible in `13-rebook-serials-locked.png`). Another agent was probably writing to the same database at the same time. They do not change any finding below, and the final reset removed them.

---

## Verdict summary

| # | Flow | Verdict | Where it breaks |
|---|---|---|---|
| F1 | Welcome → empty account | right | Small copy issues only |
| F2 | Book a pickup | confusing | On mobile, the new pickup's detail opens about 2.5 screens below the success banner |
| F3 | Simulator: collect → receive → sanitize → outcome | right (order) / confusing (one gap) | "Mark pickup collected" is offered on a future pickup and fails only after you click it |
| F4 | Listed serial never arrives | **wrong** | No "not received / missing" state, so the pickup stays Processing forever and the certificate never unlocks |
| F5 | Certificate after Complete | **wrong** | Checking in a device after Complete moves the pickup back to Processing and takes the certificate back (409) |
| F6 | Cancel, then rebook | **wrong** | Serials on a cancelled pickup stay "already registered", so the customer can't rebook them |
| F7 | Unlisted device found at intake | confusing | Nothing tells the customer that a device was not on their list, and the estimate-vs-actual mismatch isn't flagged |
| F8 | Out-of-order guards (API) | right | Every illegal move answers 422 with a clear message |
| F9 | Reset / Load sample mid-flow | right | The UI stays coherent; the open detail and certificate close |
| F10 | Reload | confusing | Every reload returns to the welcome card, even in the middle of a demo |
| F11 | Mobile 375px | right (layout) / confusing (focus) | No horizontal scroll, but nothing scrolls into view after booking |
| F12 | Domain copy | confusing | "Tracked until its data is sanitized", headline "Data sanitized 4" next to legend "Sanitized 0", stat counts that leave out cancelled pickups |

---

## F1. Welcome → empty account: right

Steps: open the app, see the welcome card (`01-welcome.png`), click **Continue as Acme Corp**, see the empty state (`02-empty.png`).

- The order is correct. The welcome card names the three jobs (Book, Track, Certificate), and the empty state points to the form and offers "or load sample data (6 pickups)". A recruiter knows what to do next.
- Copy: the welcome bullet "Track every serial number to data sanitized" reads as broken English. The domain also says tracking continues past sanitization, through to the outcome.
- Copy: the empty state says "Each device is tracked until its data is sanitized." By the domain model (matt-domain §3), a device is tracked until its **outcome** (resold, donated or recycled). This sentence describes the wrong lifecycle.

**Correct flow:** keep the order. Change the copy to "Track every serial number from pickup to resale, donation or recycling".

## F2. Book a pickup: confusing (mobile)

Steps: today's date, estimate 3, paste 3 serials, click **Book pickup** (`03-after-book.png`).

- Desktop: the result is correct. The banner reads "Pickup booked for Nov 2, 2026 with 3 serial numbers.", the detail opens with 3 `Expected` rows, the certificate button is disabled with the reason "(0 of 3 so far)", and Cancel is available. The simulator sits beside the detail.
- Mobile 375px: after booking, `scrollY` was 4 and the page was 2610px tall. The detail and simulator start roughly 2.5 screens below what is visible (`m3-after-book-viewport.png` vs `m5-full.png`). A first-time user sees only the banner and the stats, with no sign that the pickup opened below.
- Data-model behaviour: the stats bar immediately counts the 3 booked serials as "Expected 3" under "Devices by status", although no device has reached Revivn yet. That matches the API, but "Devices by status" reads as inventory Revivn holds.

**Correct flow:** after booking, scroll to (or focus) the new pickup's detail on every viewport.

## F3. Simulator: collect → receive → sanitize → outcome: right order, one gap

Steps (`04`–`10`): Mark pickup collected → Receive 001 → Sanitize: destroy (confirm: "Destroy the drive in QA-FLOW-001? It can then only be recycled.") → the simulator offers **only Recycle** for 001 (`06-destroyed-offers.png`) → Receive and wipe 002, which offers Resell / Donate / Recycle → outcomes → Complete → certificate (`10-certificate.png`).

- The order matches the domain: Receive appears only after collect, Sanitize only after Receive, an outcome only after Sanitize, and a destroyed drive gets Recycle only. The progress steps advance correctly (Scheduled → Collected → Processing → Complete).
- The simulator is visually separate and labelled ("Demo only", "Customers can't do any of this"). Ops actions are not mixed into the customer view. Good.
- **Gap:** on a scheduled pickup dated in the future (Nov 6), the simulator still shows **Mark pickup collected**. Clicking it returns "Pickup date is in the future, so the pickup can't be collected yet" (`14-future-collect.png`). The rule holds, but the UI offers an action it knows will fail.
- The certificate unlocks as soon as every device is sanitized, before outcomes are set (`08-cert-ready-before-outcomes.png`). That matches the PRD ("available only when every device is sanitized"), but a certificate issued at that moment has an empty or provisional Outcome column. It's acceptable; just be ready to explain it.
- The certificate's "Issued" time equals the time it was viewed (1:28 AM, the same as the last action). A certificate reissued on every view, with a new timestamp each time, is unusual for a compliance document.

**Correct flow:** hide or disable "Mark pickup collected" until the pickup date, with the reason as helper text.

## F4. A listed serial never arrives: WRONG

Steps: book 3 serials → collect → receive, sanitize and dispose 001 and 002 → leave 003 `Expected` (`07-stuck-missing-device.png`).

- Result: progress is **Processing**, the certificate is disabled with "(2 of 3 so far)", and the simulator's only option for 003 is **Receive**. There is no "not received / missing" outcome, so a device that never shows up keeps the pickup Processing and the certificate locked **forever**.
- The sample data has the same dead end: the Oct 24 pickup (collected 9 days earlier) still has `R9WT40ABCDE Galaxy Tab S8: Expected` (`17-sample-processing-expected.png`).
- This is the most common real-world case: the customer said 50 and 47 arrived (matt-domain §3, PRD open question 3). As built, the customer can't get a certificate for the 47 devices that were destroyed.

**Correct flow:** ops can mark an expected device "Not received" (a terminal state, left off the certificate and listed as an exception). The certificate then covers every device that was received, and the customer sees "1 listed device was not received".

## F5. Certificate after Complete: WRONG

Steps: after the pickup reached Complete and the certificate was printed (`09-complete.png`, `10-certificate.png`), the simulator still shows **Unlisted device: serial number / Check in device** on the Complete pickup. I checked one in through the API (`POST /pickups/80/devices {"serial_number":"QA-FLOW-LATE"}`):

```
"progress":"processing", "certificate_available":false
GET /pickups/80/certificate -> 409
```

The UI then showed "5 checked in, 4 of 5 sanitized" with the certificate button disabled (`11-complete-reopened.png`).

- A certificate the customer may already have handed to their auditor silently stops being available, and the pickup moves backward from Complete to Processing. That breaks the "nothing moves backward" story in the README.

**Correct flow:** close intake once the pickup is Complete (or once a certificate exists). A device that turns up later goes on a new pickup or a supplementary record. It never reopens a certified one.

## F6. Cancel, then rebook: WRONG

Steps: book Nov 7 with serials QA-RB-1 and QA-RB-2 → **Cancel pickup** → book again with the same serials.

- Result: "QA-RB-1 is already registered / QA-RB-2 is already registered" (`13-rebook-serials-locked.png`). The cancelled pickup still holds them as `Expected` (`12-cancelled-detail.png`).
- The PRD's cut list says "Edit or reschedule: Cancel and rebook covers it while scheduled." It doesn't: rebooking works only if the customer drops the serial list, which defeats Job 1 ("hand over the list of serial numbers").
- The error message doesn't say why (that the serials belong to a cancelled pickup), so the customer is stuck.

**Correct flow:** cancelling releases the cancelled pickup's expected serials (or marks them cancelled), so they can be listed again. Alternatively, allow rescheduling while scheduled.

## F7. Unlisted device found at intake: confusing

Steps: in the simulator, **Check in device** with QA-FLOW-004 on a pickup estimated at 3.

- The device appears in the customer's table as an ordinary row, and on the certificate, with nothing marking it as "found at intake, not on your list". The summary reads "You estimated 3. 4 checked in", but nothing flags the mismatch.
- For an IT admin, an unknown serial on their certificate is an audit question ("is that ours?").

**Correct flow:** tag the device "Added at intake" in the customer table and on the certificate, and show "1 more than estimated" / "1 listed not yet received" next to the counts.

## F8. Out-of-order guards (API): right

All tried with `curl`. Each was refused with a readable 422:

| Attempt | Response |
|---|---|
| Collect a future pickup | `pickup_date: is in the future, so the pickup can't be collected yet` |
| Add a device to a scheduled pickup | `pickup: must be collected first` |
| Sanitize an `expected` device | `status: can't go from expected to sanitized` |
| Add a device to a cancelled pickup | `pickup: must be collected first` |
| Cancel a collected pickup | `status: can't go from collected to cancelled` |
| Book in the past | `pickup_date: can't be in the past` |
| Certificate with unsanitized devices | 409 |

The UI matches: a cancelled pickup has no Cancel button, and its simulator says "This pickup was cancelled. Nothing to simulate." (`12-cancelled-detail.png`); Cancel disappears after collect. One small mismatch in wording: adding a device to a **cancelled** pickup says "must be collected first", which suggests it could still be collected.

## F9. Reset / Load sample mid-flow: right

- With a detail open, **Load sample data** asks "Replace all pickups with the 6 sample pickups?", closes the detail, and shows 6 rows and the banner "Sample data loaded: 6 pickups." (`16-load-sample-midflow.png`).
- With the certificate open, **Reset demo** asks "Delete all pickups and start with an empty account?", closes the certificate and detail, and returns to the empty state (`19-reset-midflow.png`). Nothing is left stale.
- Copy: "Delete all pickups" contradicts the "nothing is ever deleted" chain-of-custody pitch when a recruiter clicks it. It is a demo control, but say it out loud, or word it "Clear demo data".

## F10. Reload: confusing

- Every reload returns to the welcome card (`15-reload-welcome.png`), and the open pickup or certificate is lost. The README documents this, but a recruiter who presses F5 mid-demo, or an IT admin who refreshes to see an update, lands on a marketing card and has to click Continue and find the pickup again.

**Correct flow:** show the welcome once per session (sessionStorage), and keep the selected pickup in the URL (`?pickup=80`).

## F11. Mobile 375px: right layout, confusing focus

- No horizontal overflow at any step (`scrollWidth` 375; no element wider than the viewport). The tables collapse into stacked cards (`m5-full.png`). Buttons are large enough to tap.
- The issue is the scroll position from F2: after booking, the detail and simulator are far below. The simulator comes after the detail, so the full ops loop on a phone means scrolling about 3,000px.

## F12. Domain copy: confusing

- The empty state and welcome say tracking ends at "data sanitized" (F1). It ends at the outcome.
- The headline stat **Data sanitized 4** sits next to the legend **Sanitized 0** (`10-certificate.png`): "Sanitized" in the legend means "sanitized, no outcome yet". A reader sees a contradiction. Rename the legend entry to "Awaiting outcome" or "Sanitized, no outcome yet".
- The **Pickups** stat leaves out cancelled pickups (6 sample rows showed "5 Pickups"; 7 rows showed "6"), with no label saying so.
- "Checked in" is used consistently and matches the API ("Checked in = total − expected"). "Wiped" and "Drive destroyed" are used correctly, and only destroyed drives are restricted to Recycle. Good.
- "Repurposed: 2 of 4 devices with an outcome (50%)" counts resold + donated. That's correct, but it is a new term that appears nowhere else.

---

## Top 5 wrong-flow issues

1. **F4: a listed serial that never arrives blocks the pickup forever.** There is no "not received" state, so the pickup stays Processing and the certificate never unlocks. The sample data's Oct 24 pickup is already stuck this way.
2. **F5: a Complete, certified pickup can be reopened.** The simulator still offers "Check in device" after Complete. Using it moves progress back to Processing and the certificate answers 409.
3. **F6: cancel-and-rebook doesn't work with serials.** A cancelled pickup keeps its serials registered, so rebooking fails with "already registered". The PRD relies on cancel-and-rebook as the reschedule path.
4. **F3: "Mark pickup collected" is offered on future pickups** and fails only after the click. The simulator should show only the moves that are legal now.
5. **F7 / F2: the customer isn't told what changed or where to look.** Devices added at intake aren't marked, the estimate-vs-actual mismatch isn't flagged, and on mobile the new pickup opens off-screen after booking.

Also worth fixing before the demo: the "tracked until sanitized" copy (F1/F12), and reload dropping back to the welcome card (F10).

No test framework detected for the frontend UI (the backend has Minitest; the frontend has only `node --test` for helpers).
