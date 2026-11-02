# v3 fix list + contract addendum (binding for builders)

Sources: harsh-review.md, bug-hunt.md, flow-check.md, brainstorm.md, private grilling notes.
API-v2.md stays valid except where this file changes it. Builders update API-v2.md (backend) to match.

## Backend changes (Rails, test-first)

B1. New device status `not_received` (warehouse marks a listed serial that never arrived).
    - Transition: `expected -> not_received` only. Terminal. Action: `POST /devices/:id/mark_not_received` -> 200 whole pickup.
    - Allowed only when pickup is `collected`; else 422 `{status:[...]}`.
    - `device_counts` gains key `not_received`.
B2. Progress + certificate rules (replace current):
    - `complete` = pickup collected AND >=1 device AND every device in resold/donated/recycled/not_received.
    - `certificate_available` = pickup collected AND no device in expected/received AND >=1 device sanitized-or-later.
B3. Persisted certificate: table `certificates` (pickup_id unique FK, number string unique e.g. "CERT-000042" from id, issued_at datetime).
    - `GET /pickups/:id/certificate`: if available and none exists -> create once; return stored one. 409 if not available and none exists.
    - Response adds `"certificate_number"`, `issued_at` is the stored time (stable across reads), devices list excludes not_received
      but adds `"not_received_serials": [...]`.
    - Once a certificate exists the pickup is LOCKED: add device -> 422 `{"pickup":["is closed: certificate CERT-000042 already issued"]}`;
      mark_not_received also 422. Pickup summary JSON adds `"certificate_number": null|"CERT-..."`.
B4. Audit trail: table `device_events` (device_id FK, from_status nullable, to_status, created_at). Written in exactly one place
    (ForwardOnly#move_to inside the existing lock) plus on device creation (from nil). Device JSON adds
    `"history": [{"status": "...", "at": "<iso8601>"}]` ordered oldest first. Certificate device rows add `received_at`.
B5. Server "today": `GET /customer` response adds `"today": "YYYY-MM-DD"` (Date.current, Eastern). Frontend uses it.
B6. Cancel releases serials: on cancel, the pickup's `expected` devices move to `not_received` (via move_to, so audited).
    Serial uniqueness becomes a partial unique index `WHERE status != 'not_received'` + matching validation, so the serial can be rebooked.
B7. Demo hardening: `POST /demo/reset` requires `Content-Type: application/json` (else 415 `{"error":"JSON required"}`) and accepts
    only boolean `sample` (non-boolean -> 422). Guard = not production AND `ENV["DEMO_RESET_DISABLED"]` blank. db/seeds.rb aborts in production.
    DemoData sample serials are prefixed with the customer id (e.g. "A6-C02...") so another customer's serial can't 500 the reset.
B8. Booking RecordNotUnique race -> 422 under `serial_numbers` key (booking form shows it). Non-array `serial_numbers` -> 422.
B9. Docs: update API-v2.md, decisions.md (fix stale ADR-002/005/006 lines; add ADR-009 not_received, ADR-010 persisted certificate + lock,
    ADR-011 device_events). README is the frontend builder's job.

## Frontend changes (React, test-first for pure helpers)

F1. Use `today` from GET /customer for date min, prefill, "past pickup" flag, and whether "Mark collected" is offered (hide when date > today).
F2. Certificate: on any refetch error, clear the stored certificate (no stale Print). Show `certificate_number`, stable `issued_at`,
    `received_at` per device, and a "Not received" list. `forget()`/reset closes the certificate.
F3. Ghost-pickup race: ignore responses that started before the latest reset (generation counter). Disable every warehouse/demo/check-in
    button while its request is in flight (no double-submit errors).
F4. Simulator: "Mark not received" for expected devices; hide "Check in device" and not-received actions once certificate_number exists
    (show "Intake closed: certificate CERT-... issued").
F5. Detail: per-device history (compact timeline: status + time); badge "Unlisted" for devices that had no `expected` event;
    mismatch note when checked-in count != estimate after collect.
F6. Welcome card + topbar read the customer name from GET /customer (no hardcoded Acme). After booking on mobile, scroll detail into view.
F7. Copy/stats: lifecycle copy ends at outcome, not "sanitized"; headline stat labels consistent with legend; Pickups count says "active"
    or includes cancelled explicitly; reset confirm wording "Reset demo data".
F8. README: chain-of-custody claim now backed by history; "nothing is deleted except the demo reset" stated once; demo script updated
    (not_received, certificate number, intake lock).
