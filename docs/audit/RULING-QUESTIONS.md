# Ruling questions (phase 2)

Read the 4 audits in this folder first: matt-domain.md, ecc-product.md, superpowers-review.md, gstack-qa.md.
All agree: lifecycle moves to per-DEVICE, add sanitize (wipe/destroy) step, outcomes branch (resold/donated/recycled),
customer view (not ops), no hard delete, certificate, fix stale React state, PRD in repo.

They disagree on:

## Q1. How do devices enter the system?
- A (ECC): customer pastes serial numbers when booking -> devices created in `expected` state; warehouse marks each `received`.
- B (Matt): customer gives `estimated_device_count`; Device rows created by warehouse at intake, starting `received`.
- C: hybrid: serials optional at booking (expected), warehouse can add unexpected devices at intake.

## Q2. Pickup status?
- A (Matt): store only scheduled / collected / cancelled; "processing"/"complete" computed from devices.
- B: store full pickup status column (scheduled, collected, processing, complete, cancelled) updated by callbacks.

## Q3. How do status changes happen in a customer-view demo?
- A (ECC): customer screen read-only; separate clearly labeled "Warehouse simulator (demo)" panel/control drives collect/receive/sanitize/dispose.
- B: two tabs: Customer portal | Revivn ops.

Constraint: buildable in ~1 day, every line explainable by the user in a Revivn coding interview, no new gems/npm packages.
Answer each with letter + max 3 lines why.

## FINAL RULING (4 skill votes)
- Q1: C (hybrid) — matt C, superpowers C, ecc council C, gstack B. Majority 3-1.
- Q2: A (store scheduled/collected/cancelled; processing/complete derived) — 4-0.
- Q3: A (read-only customer screen + labeled "Warehouse simulator (demo)" panel) — 4-0.
