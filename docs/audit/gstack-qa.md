# QA Report: Laptop Pickup Tracker (gstack /qa-only)

- **Date:** 2026-11-01
- **Target:** http://localhost:5173 (Vite + React SPA, proxies `/pickups` to Rails on :3000)
- **Driver:** gstack headless browser (`$B`) plus Playwright scripts for timezone, network-failure, mobile and keyboard runs (Aside is not available on Windows)
- **Mode:** Full, report only. No code was edited or read.
- **Test data:** every record created used a `QA-` prefix. All of them were deleted at the end; the API returns 0 `QA-` rows.
- **Screenshots:** `docs/audit/shots/` (26 files)

## Health score: 83 / 100 (provisional: Performance not scored)

| Category | Weight | Score | Notes |
|---|---|---|---|
| Console | 15% | 70 | No JS exceptions. Browser logs `Failed to load resource: 422` on every server-side validation failure (1 distinct error) |
| Links | 10% | 100 | Single-page app, no broken destinations |
| Visual | 10% | 92 | ISSUE-003 |
| Functional | 20% | 76 | ISSUE-001, 002, 006 |
| UX | 15% | 80 | ISSUE-007, 008, 009, 010, 011 |
| Performance | 10% | not scored | Loads feel instant locally, but nothing was measured |
| Content | 5% | 100 | Copy is clear, error messages are readable |
| Accessibility | 15% | 84 | ISSUE-004, 005 |

Score = 74.5 / 0.90 tested weight = 82.8, rounded to 83.

| Severity | Count |
|---|---|
| Critical | 0 |
| High | 0 |
| Medium | 7 |
| Low | 4 |

## What passed

| Flow | Result | Evidence |
|---|---|---|
| Valid schedule | Row created, form clears, stats update, persists after reload | shots/08-valid.png |
| Blank submit | Three inline errors: "Company can't be blank", "Device count is not a number", "Pickup date can't be blank" | shots/02-blank-submit.png |
| 0 devices | "Device count must be greater than 0", other fields keep their values, `aria-invalid` and `aria-describedby` set | shots/03-zero-devices.png |
| 10001 devices | "Device count must be less than or equal to 10000" | shots/04-10001.png |
| 2.5 devices | "Device count must be an integer" | (text check) |
| Whitespace-only company | "Company can't be blank" | shots/06-whitespace.png |
| 249-char company | "Company is too long (maximum is 100 characters)" | shots/07-long-name.png |
| Backward status | Earlier steps are disabled in the UI. API also rejects it: `PATCH status=scheduled` returns 422 "can't go from refurbished back to scheduled" | shots/23-skip-after.png |
| Delete, cancel | Confirm text "Delete the QA-Valid Corp pickup? This can't be undone."; row kept, API still 200 | (dialog log) |
| Delete, confirm | Row removed, API returns 404 afterwards | shots/11-after-delete.png |
| Sort by date | Ascending by default, toggles to descending, `aria-sort` updates | shots/13-sorted-desc.png |
| Reload persistence | Creates, status changes and deletes all survive reload | (text check) |
| Double submit | Button shows "Scheduling…" and is disabled. Second click and Enter blocked; 1 row created | shots/18-submitting.png |
| POST fails (network abort) | Alert "Couldn't schedule the pickup. The server didn't respond."; form values kept | shots/17-post-fail.png |
| GET fails (500 or abort) | Banner "Couldn't load pickups. Check that the Rails server is running on port 3000, then retry." plus a Retry button | shots/15-load-500.png, shots/16-load-abort.png |
| Timezone off-by-one | Tested in Honolulu, Los Angeles, New York, UTC, Tokyo and Kiritimati (UTC+14). Every date matches the stored `pickup_date`, so there is no off-by-one | shots/14-tz-kiritimati.png |
| Keyboard tab order | Company > devices > date > Schedule > sort > per-row enabled steps > Delete. Focus ring is visible on all of them | shots/20-keyboard-focus.png |
| Keyboard submit | Typing all fields and pressing Enter creates the pickup | (API check) |
| Mobile 375px (normal data) | No horizontal scroll (scrollWidth 375). The table becomes stacked cards | shots/21-mobile-375-clean.png, shots/21b-mobile-table.png |

## Issues

### ISSUE-001: A failed status change or delete leaves the UI out of sync with the server, and "Try again" can never succeed
**Severity:** Medium | **Category:** Functional

**Steps to reproduce (status):**
1. Load the app. Row `QA-Past` shows "Scheduled".
2. In another tab or client, advance that pickup to Donated (`PATCH /pickups/12 {"pickup":{"status":"donated"}}` returns 200).
3. In the original tab, click the "Picked up" step on that row.

**Expected:** The app refetches or shows the real current status ("This pickup is already Donated").
**Actual:** The server returns 422. The banner says "Couldn't update the status. Try again." and the row still shows "Scheduled", which is wrong. Retrying fails every time until a manual reload.

**Steps to reproduce (delete):**
1. Load the app. Delete `QA-Past` from another client (DELETE returns 204).
2. Click Delete on that row and confirm.

**Expected:** The row disappears, because it is already gone.
**Actual:** The server returns 404 and the banner says "Couldn't delete the pickup. Try again." The ghost row stays. Retrying fails forever.

The banner also appears at the top of the page, far from the row the user clicked. On a long list it is off-screen.

**Evidence:** shots/10-stale-status-error.png, shots/12-stale-delete.png

---

### ISSUE-002: The stepper allows skip-ahead with no confirmation, and because backward moves are blocked, a misclick is permanent
**Severity:** Medium | **Category:** Functional

**Steps to reproduce:**
1. Schedule `QA-Skip`, 6 devices, Dec 28 2026. It shows "Scheduled".
2. Click the 4th stepper segment (Donated).

**Expected:** Either only the next step can be selected, or a confirmation appears before skipping stages, especially since the move cannot be undone.
**Actual:** One click jumps Scheduled straight to Donated. No dialog appears (0 dialogs fired). "Scheduled" and "Picked up" become disabled, and the API also blocks going back. The only fix is to delete and re-enter the pickup. A pickup dated in the future (Dec 20 or Dec 28) can also be marked Picked up or Donated before the pickup has happened.

**Evidence:** shots/23-skip-before.png, shots/23-skip-after.png, shots/22-keyboard-status.png

---

### ISSUE-003: A long company name with no spaces breaks the layout on desktop and mobile
**Severity:** Medium | **Category:** Visual

**Steps to reproduce:**
1. Schedule a company named `QA-` + 97 × `W` (100 characters, which validation accepts).
2. View at 1280px wide, then at 375px.

**Expected:** The name wraps or truncates with an ellipsis. The page never scrolls sideways.
**Actual:** At 1280px the document scrollWidth is 2361px. The Company column stretches so far that the "Pickup date" column wraps to 3 lines ("Oct / 20, / 2026") on every row, and the right part of the table is pushed off-screen. At 375px the scrollWidth is 1540px and the form card is clipped on the right. With normal names, mobile is fine (375px).

**Evidence:** shots/09-100char.png, shots/19-mobile-375.png, shots/19b-mobile-375-viewport.png

---

### ISSUE-004: Keyboard focus drops to `<body>` after a status change and after a delete
**Severity:** Medium | **Category:** Accessibility

**Steps to reproduce:**
1. Use Tab to reach the "Picked up" step on a Scheduled row and press Enter.
2. Check `document.activeElement`.
3. Use Tab to reach that row's Delete button, press Enter and accept the dialog.

**Expected:** Focus stays in the row, for example on the next step, or moves to a sensible neighbour such as the next row's Delete button.
**Actual:** Focus goes to `BODY` both times. The step just pressed becomes disabled, and the deleted row is removed from the DOM. A keyboard or screen-reader user is sent back to the top of the page and has to tab through the form again.

**Evidence:** shots/22-keyboard-status.png (Playwright log: "focus after status via keyboard: BODY", "focus after delete: BODY")

---

### ISSUE-005: Stepper segments are unlabeled bars with touch targets below the WCAG 2.2 minimum
**Severity:** Medium | **Category:** Accessibility

**Steps to reproduce:**
1. Open at 375px with touch emulation.
2. Measure the stepper buttons.

**Expected:** Targets of at least 24×24 CSS px (WCAG 2.2 SC 2.5.8 AA), ideally 44×44. A visible hint that the bars are clickable.
**Actual:** Each step is 22×28px. That is narrower than 24px, and the 4 steps sit right next to each other, which makes ISSUE-002 misclicks easy. The steps have no visible text, so nothing on screen tells a sighted user that the bars are buttons or what each one does (only `title`/`aria-label`). The group's accessible name is fine: "Status for <company>".

**Evidence:** shots/21b-mobile-table.png, shots/23-skip-before.png

---

### ISSUE-006: Pickups dated in the past are accepted as "Scheduled", with no warning
**Severity:** Medium | **Category:** Functional

**Steps to reproduce:**
1. Schedule `QA-Past`, 3 devices, date 2020-01-01.

**Expected:** Either a validation error ("Pickup date can't be in the past") or a visible overdue marker.
**Actual:** The pickup saves as Scheduled for Jan 1, 2020 and sorts to the top of the list, looking exactly like any upcoming pickup.

**Evidence:** shots/05-past.png, shots/09-100char.png (top row)

---

### ISSUE-007: No way to sort on mobile
**Severity:** Low | **Category:** UX

**Steps to reproduce:** Open at 375px and look for the "Pickup date" sort control.
**Expected:** A sort control is available in the card layout.
**Actual:** The header button is rendered at 0×0. The cards always show ascending date order.
**Evidence:** shots/21-mobile-375-clean.png

---

### ISSUE-008: When the API is down, the page shows zeros as if they were real data and leaves the form active
**Severity:** Low | **Category:** UX

**Steps to reproduce:** Make `GET /pickups` fail (500 or connection refused) and load the page.
**Expected:** Stats show a placeholder (such as "—"), and the form is disabled or warns that it will fail.
**Actual:** The banner and Retry button appear, which is good. But "0 Pickups / 0 Devices / 0 devices, 0 pickups" displays as if the account were empty, and the form invites a submission that will fail. The banner also mentions "Rails server ... port 3000", which is developer wording rather than user wording.
**Evidence:** shots/15-load-500.png, shots/16-load-abort.png

---

### ISSUE-009: No success confirmation after scheduling a pickup
**Severity:** Low | **Category:** UX

**Steps to reproduce:** Schedule a valid pickup dated far in the future.
**Expected:** A brief "Pickup scheduled for Acme, Dec 5" message, announced through a live region, or the new row highlighted or scrolled into view.
**Actual:** The form clears silently and focus stays in the date field. The new row is inserted in date order, often off-screen. The page has no `aria-live` or `role=status` region, so screen readers announce nothing.
**Evidence:** shots/08-valid.png

---

### ISSUE-010: The status model is linear (Refurbished, then Donated), but the copy says "refurbishing **or** donation"
**Severity:** Low | **Category:** UX

**Steps to reproduce:** Look at a Donated row (Northwind Health). All 4 segments are filled, so it went through Refurbished. Compare with the subtitle.
**Expected:** Refurbished and Donated are alternative outcomes (resell versus donate). For an ITAD workflow there would also be a recycled or data-destroyed outcome.
**Actual:** Donated is shown as the step after Refurbished. The "Devices by stage" totals count each pickup in only one stage, so a reader cannot tell how many devices were refurbished in total.
**Evidence:** shots/01-initial.png

---

### ISSUE-011: Small friction points
**Severity:** Low | **Category:** UX

- The sort direction resets to ascending on reload (it is not kept in the URL or storage). Evidence: shots/13-sorted-desc.png
- The Company input has no `maxlength`, so a user can type 249 characters and only learns about the 100-character limit after submitting. Evidence: shots/07-long-name.png
- A status change takes effect on a single click with no undo toast (see ISSUE-002).

## Console health

- JS exceptions or unhandled rejections: **0** across all flows.
- Browser network logs: `Failed to load resource: 422 (Unprocessable Content)` on every server-validated form error and stale status change, and `404 (Not Found)` on the stale delete (that one is counted under ISSUE-001).

## Missing flows a real user would expect

1. **Edit a pickup:** fix the device count, date or company after creating it. Today the only option is delete and recreate.
2. **Undo or correct a status:** an admin override or an "undo" toast, given that backward moves are blocked.
3. **Search or filter:** by company, and by status (for example, "show only Scheduled").
4. **Sort by other columns:** company, device count, status.
5. **Overdue and today views:** scheduled pickups whose date has passed, and pickups due this week.
6. **Pickup details:** address, contact person or phone, time window, notes, device types (laptops versus phones), serials.
7. **Audit trail:** who changed the status and when (the API has `updated_at` only). ITAD customers need chain of custody.
8. **Certificates:** a data-destruction or donation certificate per pickup, the core ITAD deliverable.
9. **Recycled / data-wiped outcome** alongside Refurbished and Donated.
10. **Export:** CSV or PDF of pickups for reporting.
11. **Pagination or virtualization** once the list grows past a few dozen rows.
12. **Auth and multi-tenant scoping:** any visitor can delete any pickup.

## Top 3 things to fix

1. ISSUE-001: refetch or reconcile on 404/422 so the UI never shows stale rows.
2. ISSUE-002: block or confirm skip-ahead and add undo, since moves are irreversible.
3. ISSUE-003: wrap or truncate long company names so the layout cannot overflow.
