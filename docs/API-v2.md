# Pickup Tracker v2: API contract

This is the contract both builders code against. The BACKEND track must return exactly these shapes. The FRONTEND track may rely on every field listed here and on nothing else. If something is not written here, it does not exist.

Decisions behind it: `docs/audit/RULING-QUESTIONS.md` (FINAL RULING), `docs/PRD-v2.md`, and the v3 addendum `docs/audit/FIX-LIST-v3.md` (B1-B9, folded in below).

## 1. Conventions

| Topic | Rule |
|---|---|
| Base URL | Rails on `http://localhost:3000`. The Vite dev server proxies `/customer`, `/pickups` and `/devices` to it, so the browser calls relative paths (`/pickups`). |
| Format | JSON in, JSON out. Send `Content-Type: application/json`. |
| Auth | None. Every request acts as the one seeded demo customer, "Acme Corp" (`current_customer` on the server). Data of any other customer is invisible: it answers 404, never 403. |
| Ids | Integers. |
| Dates | `pickup_date` is a plain date string `"YYYY-MM-DD"`. Parse it from its parts, never with `new Date("YYYY-MM-DD")` (that reads it as UTC midnight). |
| Timestamps | ISO 8601 strings with milliseconds and a UTC offset, in the server zone `Eastern Time (US & Canada)`, for example `"2026-11-01T14:00:00.000-05:00"`. `null` when not set. |
| "Today" | The server's `Date.current` in Eastern time, returned as `today` by `GET /customer` (4.1). Use that value, never the browser's clock, for date minimums, prefills and "past pickup" flags. Today is 2026-11-01 in all examples. |
| Numbers in requests | `estimated_device_count` may be sent as an integer or a numeric string (`3` or `"3"`). An `<input type="number">` value can be sent as is. |
| Methods | Only `GET` and `POST`. There is no `PATCH`, `PUT` or `DELETE`: they answer 404. |
| Pickup actions | Every endpoint that changes data returns the **whole updated pickup** in the "pickup detail" shape (section 3.2), so the client replaces one object and sees the new progress, counts and device rows. |

## 2. Status values

### 2.1 Pickup `status` (stored)

| Value | Meaning |
|---|---|
| `scheduled` | Booked by the customer. Every pickup starts here. It can't be set by the client on create. |
| `collected` | Revivn picked the devices up. |
| `cancelled` | The customer cancelled before collection. The record is kept (no deletes, chain of custody). Its `expected` devices move to `not_received`, which frees their serials for a new booking. |

Allowed moves (anything else answers 422):

| From | Action | To | Extra guard |
|---|---|---|---|
| `scheduled` | `POST /pickups/:id/collect` | `collected` | `pickup_date` must be today or earlier |
| `scheduled` | `POST /pickups/:id/cancel` | `cancelled` | none |
| `collected` | (none) | | final as a stored status |
| `cancelled` | (none) | | final |

Repeating an action is not a no-op: cancelling a cancelled pickup answers 422 `"can't go from cancelled to cancelled"`.

### 2.2 Pickup `progress` (computed, read-only)

`progress` is what the customer sees. It is never stored. The server computes it on every response:

| `status` | Devices on the pickup | `progress` |
|---|---|---|
| `scheduled` | any | `scheduled` |
| `cancelled` | any | `cancelled` |
| `collected` | none, or all `expected` | `collected` |
| `collected` | at least 1 device, and every device is `resold`, `donated`, `recycled` or `not_received` | `complete` |
| `collected` | otherwise (at least 1 device is past `expected` and at least 1 is not terminal) | `processing` |

The rows are checked top to bottom for a collected pickup: `complete` first, then `processing`, then `collected`.

### 2.3 Device `status` (stored)

| Value | Meaning | Terminal |
|---|---|---|
| `expected` | Serial listed by the customer at booking. Not yet at Revivn. | no |
| `received` | Checked in at the Revivn warehouse. | no |
| `not_received` | Listed at booking but never arrived (marked by the warehouse after collection), or released when the pickup was cancelled. Never sanitized. Its serial no longer counts as registered. | yes |
| `sanitized` | Data destroyed. `sanitization_method` and `sanitized_at` are set. | no |
| `resold` | Sold again. | yes |
| `donated` | Given to a nonprofit. | yes |
| `recycled` | Broken down for materials. | yes |

`sanitization_method` is `null` until sanitize, then `"wipe"` (software overwrite, device reusable) or `"destroy"` (drive physically destroyed). Once set it never changes.

Allowed moves (anything else answers 422):

| From | Action | To | Extra guard |
|---|---|---|---|
| (new, from booking) | `POST /pickups` with `serial_numbers` | `expected` | pickup is being created |
| (new, at intake) | `POST /pickups/:pickup_id/devices` | `received` | pickup `status` is `collected` |
| `expected` | `POST /devices/:id/receive` | `received` | pickup `status` is `collected` |
| `expected` | `POST /devices/:id/mark_not_received` | `not_received` | pickup `status` is `collected`; no certificate issued |
| `expected` | `POST /pickups/:id/cancel` (all of the pickup's `expected` devices) | `not_received` | pickup was `scheduled` |
| `received` | `POST /devices/:id/sanitize` | `sanitized` | `sanitization_method` is `wipe` or `destroy` |
| `sanitized` | `POST /devices/:id/dispose` `resold` / `donated` | `resold` / `donated` | `sanitization_method` is `wipe` |
| `sanitized` | `POST /devices/:id/dispose` `recycled` | `recycled` | none |
| `resold`, `donated`, `recycled`, `not_received` | anything | (rejected) | terminal |

Rules this encodes, each enforced in the model and covered by a test:
- **Sanitize before outcome:** no device reaches `resold`, `donated` or `recycled` without passing `sanitized`.
- **Destroyed means recycled only:** `sanitization_method == "destroy"` allows only `recycled`.
- **No backward moves, no skips:** one step at a time along the table.
- Every device is treated as data-bearing (no monitors-without-storage branch in v2).

What the client should offer per device status (the "next actions"):

| Device status | Buttons |
|---|---|
| `expected` | Receive, Mark not received |
| `received` | Sanitize (wipe), Sanitize (destroy) |
| `sanitized` with `wipe` | Resell, Donate, Recycle |
| `sanitized` with `destroy` | Recycle |
| terminal (incl. `not_received`) | none |

Receive and the warehouse steps only work once the pickup is `collected`; show them only then. Once the pickup has a `certificate_number`, intake is closed: hide "Check in device" and "Mark not received".

Every move above (and every device creation) adds one entry to the device's `history` (3.3). Nothing else writes it.

## 3. Shapes

### 3.1 Pickup summary (used by `GET /pickups`)

```json
{
  "id": 4,
  "pickup_date": "2026-11-01",
  "estimated_device_count": 3,
  "status": "scheduled",
  "progress": "scheduled",
  "device_counts": {
    "expected": 3,
    "received": 0,
    "not_received": 0,
    "sanitized": 0,
    "resold": 0,
    "donated": 0,
    "recycled": 0,
    "total": 3
  },
  "certificate_available": false,
  "certificate_number": null,
  "created_at": "2026-11-01T09:12:40.120-05:00",
  "updated_at": "2026-11-01T09:12:40.120-05:00"
}
```

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `pickup_date` | string `YYYY-MM-DD` | |
| `estimated_device_count` | integer 1..10000 | The customer's guess. Compare with `device_counts.total`. |
| `status` | `scheduled` \| `collected` \| `cancelled` | Section 2.1 |
| `progress` | `scheduled` \| `collected` \| `processing` \| `complete` \| `cancelled` | Section 2.2 |
| `device_counts` | object | All eight keys are always present, zero when none. `total` = number of device rows. "Checked in" = `total - expected - not_received`. "Sanitized so far" = `sanitized + resold + donated + recycled`. |
| `certificate_available` | boolean | `true` only when the pickup is `collected`, no device is `expected` or `received`, and at least 1 device is `sanitized` or later. `not_received` devices don't block it. Same rule as the 409 in 4.9 (before a certificate exists). |
| `certificate_number` | string or `null` | `"CERT-000042"` once the certificate has been issued (first `GET /pickups/:id/certificate`), else `null`. A non-null value means the pickup is closed to intake. |
| `created_at`, `updated_at` | timestamp | |

There is no `company`, `device_count` or `customer_id` field.

### 3.2 Pickup detail (used by `GET /pickups/:id` and every action)

The summary plus a `devices` array, ordered by device `id` ascending (booking order, then intake order):

```json
{
  "id": 2,
  "pickup_date": "2026-10-23",
  "estimated_device_count": 6,
  "status": "collected",
  "progress": "processing",
  "device_counts": { "expected": 1, "received": 3, "not_received": 0, "sanitized": 2, "resold": 0, "donated": 0, "recycled": 0, "total": 6 },
  "certificate_available": false,
  "certificate_number": null,
  "created_at": "2026-11-01T09:12:40.120-05:00",
  "updated_at": "2026-11-01T09:12:40.120-05:00",
  "devices": [
    {
      "id": 7,
      "pickup_id": 2,
      "serial_number": "C02HM8Z1Q6L4",
      "model": "MacBook Pro 16 (2021)",
      "status": "sanitized",
      "sanitization_method": "wipe",
      "sanitized_at": "2026-10-25T14:00:00.000-04:00",
      "history": [
        { "status": "expected", "at": "2026-11-01T09:12:40.130-05:00" },
        { "status": "received", "at": "2026-11-01T09:20:02.411-05:00" },
        { "status": "sanitized", "at": "2026-11-01T09:31:15.020-05:00" }
      ],
      "created_at": "2026-11-01T09:12:40.130-05:00",
      "updated_at": "2026-11-01T09:12:40.150-05:00"
    }
  ]
}
```

### 3.3 Device

| Field | Type | Notes |
|---|---|---|
| `id` | integer | |
| `pickup_id` | integer | |
| `serial_number` | string, 1..50 chars | Stored trimmed and UPPERCASED. Unique across all devices that are not `not_received` (a released serial can be booked again, so rows may share a serial when all but one are `not_received`). Long serials have no spaces: the UI must wrap them. |
| `model` | string up to 100 chars, or `null` | Free text, e.g. "ThinkPad T14". `null` for serials pasted at booking. |
| `status` | see 2.3 | |
| `sanitization_method` | `"wipe"` \| `"destroy"` \| `null` | |
| `sanitized_at` | timestamp or `null` | |
| `history` | array of `{ "status", "at" }` | Every status the device entered, oldest first: one entry at creation (`expected` from booking, or `received` from intake) and one per move. `at` is a timestamp. A device whose first entry is not `expected` was not listed by the customer ("Unlisted"). Demo sample data is backdated: each move carries a realistic past time (booked, then received, then sanitized, then outcome), and `sanitized_at` equals the time of the `sanitized` entry. |
| `created_at`, `updated_at` | timestamp | |

### 3.4 Error bodies

| Code | Body | When |
|---|---|---|
| 400 | `{ "error": "<message>" }` | The required root key (`pickup` or `device`) is missing. Don't parse the message. |
| 404 | `{ "error": "Pickup not found" }`, `{ "error": "Device not found" }` or `{ "error": "Customer not found" }` | Unknown id, or the record belongs to another customer. `Customer not found` means the database wasn't seeded. Unknown routes (including any `PATCH`/`DELETE`) also answer 404, with a body that is not guaranteed to be JSON. |
| 409 | `{ "error": "Certificate is available once every device in this pickup is sanitized" }` | Certificate requested too early (4.9 only). |
| 415 | `{ "error": "JSON required" }` | `POST /demo/reset` without `Content-Type: application/json` (4.10 only). |
| 422 | `{ "<field>": ["<message>", ...], ... }` | A validation or transition rule failed. Keys are snake_case attribute names. Only failing fields appear. |

Turning a 422 body into sentences (the frontend does this in `errorMessages`): replace `_` with a space, capitalise the first letter, then join with the message. `{ "status": ["can't go from received to resold"] }` becomes "Status can't go from received to resold". `{ "pickup": ["must be collected first"] }` becomes "Pickup must be collected first".

## 4. Endpoints

| # | Method | Path | Who uses it | Success |
|---|---|---|---|---|
| 4.1 | GET | `/customer` | Customer view header | 200 |
| 4.2 | GET | `/pickups` | Customer list | 200 |
| 4.3 | GET | `/pickups/:id` | Customer detail panel | 200 |
| 4.4 | POST | `/pickups` | Customer booking form | 201 |
| 4.5 | POST | `/pickups/:id/cancel` | Customer (only while scheduled) | 200 |
| 4.6 | POST | `/pickups/:id/collect` | Warehouse simulator (demo) | 200 |
| 4.7 | POST | `/pickups/:pickup_id/devices` | Warehouse simulator: add a device at intake | 201 |
| 4.8a | POST | `/devices/:id/receive` | Warehouse simulator | 200 |
| 4.8b | POST | `/devices/:id/sanitize` | Warehouse simulator | 200 |
| 4.8c | POST | `/devices/:id/dispose` | Warehouse simulator | 200 |
| 4.8d | POST | `/devices/:id/mark_not_received` | Warehouse simulator | 200 |
| 4.9 | GET | `/pickups/:id/certificate` | Customer certificate view | 200 |
| 4.10 | POST | `/demo/reset` | Demo controls: load sample data / reset (dev only) | 200 |

### 4.1 `GET /customer`

Request: no body.

200:
```json
{ "id": 1, "name": "Acme Corp", "today": "2026-11-01" }
```

`today` is the server's `Date.current` (Eastern), `YYYY-MM-DD`.

Errors: 404 `{ "error": "Customer not found" }` if the database was not seeded.

### 4.2 `GET /pickups`

Request: no body, no query params.

200: an array of **pickup summaries** (3.1), at most 200, ordered by `pickup_date` descending, then `id` descending. Upcoming pickups come first, so they are never cut off by the limit. No `devices` key. Only the current customer's pickups. Cancelled pickups are included (the UI shows them with the `cancelled` progress).

Errors: 404 `Customer not found` only.

### 4.3 `GET /pickups/:id`

200: **pickup detail** (3.2).

Errors: 404 `{ "error": "Pickup not found" }` (also for another customer's pickup).

### 4.4 `POST /pickups`

Request:
```json
{
  "pickup": {
    "pickup_date": "2026-11-05",
    "estimated_device_count": 3,
    "serial_numbers": ["C02ABC123XYZ", "c02abc124xyz ", ""]
  }
}
```

| Field | Required | Rule |
|---|---|---|
| `pickup_date` | yes | `YYYY-MM-DD`, today or later |
| `estimated_device_count` | yes | integer, 1 to 10000 |
| `serial_numbers` | no | Array of strings. Omit it or send `[]` for none. Anything else (a string, nested arrays, objects) answers 422. The server trims each entry, uppercases it, and drops empty entries. Each must be at most 50 characters, not repeated in the list, and not already registered on any device (devices that are `not_received` don't count). Each one becomes a device with status `expected`. |

Any other key, including `status`, is ignored. The new pickup always has `status: "scheduled"`.

201: **pickup detail** (3.2) of the new pickup. With the request above: `status` `scheduled`, `progress` `scheduled`, `device_counts.expected` 2, `devices` with serials `C02ABC123XYZ` and `C02ABC124XYZ`, each `status: "expected"`, `model: null`.

422 examples (keys appear only when they fail):
```json
{
  "estimated_device_count": ["is not a number"],
  "pickup_date": ["can't be blank"]
}
```
```json
{ "pickup_date": ["can't be in the past"] }
```
```json
{ "serial_numbers": ["C02ABC123XYZ is listed more than once", "C02EXP0001 is already registered"] }
```

Possible 422 messages:

| Key | Messages |
|---|---|
| `estimated_device_count` | `is not a number`, `must be an integer`, `must be greater than 0`, `must be less than or equal to 10000` |
| `pickup_date` | `can't be blank`, `can't be in the past` |
| `serial_numbers` | `<SERIAL> is listed more than once`, `<SERIAL> is already registered`, `<SERIAL> is longer than 50 characters`, `must be a list of serial numbers` |

`<SERIAL> is already registered` is also the answer when a concurrent booking takes the serial between the check and the insert; it is never a 500.

400: body without a `pickup` key, e.g. `{}`.

### 4.5 `POST /pickups/:id/cancel`

Request: no body.

200: **pickup detail** with `status: "cancelled"`, `progress: "cancelled"`. Its `expected` devices are now `not_received` (each with a history entry), so their serials can be booked again.

422:
```json
{ "status": ["can't go from collected to cancelled"] }
```
(or `"can't go from cancelled to cancelled"`)

404: `Pickup not found`.

### 4.6 `POST /pickups/:id/collect`

Request: no body.

200: **pickup detail** with `status: "collected"`. `progress` is `collected` (no devices, or only `expected` ones).

422, one or both keys:
```json
{ "pickup_date": ["is in the future, so the pickup can't be collected yet"] }
```
```json
{ "status": ["can't go from cancelled to collected"] }
```

404: `Pickup not found`.

### 4.7 `POST /pickups/:pickup_id/devices`

A device the customer didn't list, found at intake. It starts as `received`.

Request:
```json
{ "device": { "serial_number": "DMPXQ0LZJF8J", "model": "iPad Air (5th gen)" } }
```

| Field | Required | Rule |
|---|---|---|
| `serial_number` | yes | trimmed, uppercased, 1..50 chars, unique across all devices that are not `not_received` |
| `model` | no | up to 100 chars; omit, `""` or `null` are all fine (stored as sent; `""` is kept as `""`) |

201: **pickup detail** of the parent pickup, now including the new device with `status: "received"`.

422:

| Key | Messages |
|---|---|
| `serial_number` | `can't be blank`, `has already been taken`, `is too long (maximum is 50 characters)` |
| `model` | `is too long (maximum is 100 characters)` |
| `pickup` | `must be collected first` (pickup is `scheduled` or `cancelled`) |
| `pickup` | `is closed: certificate CERT-000042 already issued` (the pickup has a `certificate_number`) |

400: no `device` key. 404: `Pickup not found`.

### 4.8 Device actions

All three: no path params besides the device `id`; the device must belong to one of the current customer's pickups, otherwise 404 `{ "error": "Device not found" }`. On success: 200 with the **pickup detail** (3.2) of the device's pickup.

#### 4.8a `POST /devices/:id/receive`

Request: no body.

422:

| Key | Messages |
|---|---|
| `status` | `can't go from <current> to received` |
| `pickup` | `must be collected first` |

#### 4.8b `POST /devices/:id/sanitize`

Request:
```json
{ "sanitization_method": "wipe" }
```
`"wipe"` or `"destroy"`. Sets `status: "sanitized"`, `sanitization_method`, and `sanitized_at` to now.

422:

| Key | Messages |
|---|---|
| `status` | `can't go from <current> to sanitized` (e.g. from `expected`, or a second sanitize) |
| `sanitization_method` | `is not included in the list` (missing or unknown value) |
| `pickup` | `must be collected first` |

#### 4.8c `POST /devices/:id/dispose`

Request:
```json
{ "outcome": "resold" }
```
`"resold"`, `"donated"` or `"recycled"`.

422:

| Key | Messages |
|---|---|
| `status` | `must be one of: resold, donated, recycled` (missing or unknown `outcome`) |
| `status` | `can't go from <current> to <outcome>` (e.g. `received` to `resold`: sanitize first; or from a terminal status) |
| `status` | `can only be recycled after the drive is destroyed` (`destroy` device sent `resold` or `donated`) |

#### 4.8d `POST /devices/:id/mark_not_received`

A serial the customer listed that never arrived. Only from `expected`; terminal.

Request: no body.

422:

| Key | Messages |
|---|---|
| `status` | `can't be marked not received before the pickup is collected` (pickup is `scheduled`) |
| `status` | `can't go from <current> to not_received` (device is not `expected`) |
| `pickup` | `is closed: certificate CERT-000042 already issued` |

### 4.9 `GET /pickups/:id/certificate`

The certificate is issued once and stored. The first request when `certificate_available` is `true` creates it; every later request returns the same stored certificate (same `certificate_number`, same `issued_at`). From then on the pickup is closed to intake (4.7 and 4.8d answer 422).

200:

```json
{
  "pickup_id": 1,
  "certificate_number": "CERT-000001",
  "customer_name": "Acme Corp",
  "pickup_date": "2026-10-11",
  "standard": "NIST SP 800-88",
  "issued_at": "2026-11-01T10:05:00.000-05:00",
  "devices": [
    {
      "serial_number": "A1-C02FK3Q1MD6R",
      "model": "MacBook Pro 14 (2021)",
      "sanitization_method": "wipe",
      "sanitized_at": "2026-10-14T14:00:00.000-04:00",
      "status": "resold",
      "received_at": "2026-11-01T09:12:40.140-05:00"
    }
  ],
  "not_received_serials": []
}
```

| Field | Type | Notes |
|---|---|---|
| `pickup_id` | integer | |
| `certificate_number` | string | `"CERT-"` plus the pickup id, zero-padded to at least 6 digits. Unique. Same value as the pickup's `certificate_number`. |
| `customer_name` | string | |
| `pickup_date` | `YYYY-MM-DD` | |
| `standard` | string | Always `"NIST SP 800-88"` (the standard revivn.com names). |
| `issued_at` | timestamp | When the certificate was first issued. Stable across reads. |
| `devices` | array | Every device of the pickup except `not_received` ones, ordered by `serial_number` ascending. Each has exactly the 6 keys shown. `status` is `sanitized` (no outcome yet) or the outcome. `received_at` is when the device entered `received` (from its history), or `null` if there is no such entry. |
| `not_received_serials` | array of strings | Serials listed at booking that never arrived, ordered ascending. `[]` when none. |

409 (only while no certificate has been issued and `certificate_available` is `false`):
```json
{ "error": "Certificate is available once every device in this pickup is sanitized" }
```
404: `Pickup not found`.

### 4.10 Demo: `POST /demo/reset`

Dev/demo only (ADR-008). Deletes **only** `current_customer`'s pickups, devices, device history and certificates in one transaction, then, if `sample` is `true`, rebuilds the 6 sample pickups / 15 devices from section 5 (dated relative to today). Other customers' data is never touched.

Request:
```json
{ "sample": true }
```
The request must have `Content-Type: application/json`. `sample` must be a JSON boolean: `true` loads data; `false`, `null` or missing leaves the customer empty.

200:
```json
{ "customer": { "id": 1, "name": "Acme Corp" }, "pickups_count": 6 }
```
`pickups_count` is `6` after `sample: true`, `0` otherwise.

Errors:
- 404 `{ "error": "Not found" }` when Rails runs in production, or when the `DEMO_RESET_DISABLED` environment variable is set.
- 415 `{ "error": "JSON required" }` without a JSON content type.
- 422 `{ "sample": ["must be true or false"] }` when `sample` is not a boolean (e.g. `"true"` or `1`).
- 404 `{ "error": "Customer not found" }` if the database was not seeded.

## 5. Sample demo data (after `SAMPLE=1 bin/rails db:seed` or `POST /demo/reset {"sample": true}`, run on 2026-11-01)

One customer, "Acme Corp". Plain `bin/rails db:seed` creates only the customer, with no pickups (the app starts empty); seeds refuse to run in production. Dates are relative to the day the data is loaded. Sample serials are prefixed with `A<customer id>-` (e.g. `A1-C02FK3Q1MD6R`), so they never collide with another customer's devices.

| Pickup date | status | progress | Devices | Certificate |
|---|---|---|---|---|
| today - 21 (2026-10-11) | collected | complete | 6: 3 resold, 1 donated, 1 recycled (wipe), 1 recycled (destroy) | available (issued on first view) |
| today - 9 (2026-10-23) | collected | processing | 6: 2 sanitized (wipe), 2 received, 1 expected, 1 added at intake (received) | 409 |
| today - 2 (2026-10-30) | collected | collected | 0, estimate 8 | 409 |
| today (2026-11-01) | scheduled | scheduled | 3 expected | 409 |
| today + 3 (2026-11-04) | cancelled | cancelled | 0, estimate 4 | 409 |
| today + 6 (2026-11-07) | scheduled | scheduled | 0, estimate 25 | 409 |

The "today" pickup is the live demo: collect it, receive its devices (or mark one not received), sanitize, open the certificate (it gets its number and closes intake), then dispose.
