// Labels for every status in docs/API-v2.md section 2. Key order is display order.
export const PROGRESS_LABELS = {
  scheduled: 'Scheduled',
  collected: 'Collected',
  processing: 'Processing',
  complete: 'Complete',
  cancelled: 'Cancelled',
}
export const DEVICE_LABELS = {
  expected: 'Expected',
  received: 'Received',
  sanitized: 'Sanitized',
  resold: 'Resold',
  donated: 'Donated',
  recycled: 'Recycled',
  not_received: 'Not received',
}
export const METHOD_LABELS = { wipe: 'Wiped', destroy: 'Drive destroyed' }

// One place for every request. A failure throws an Error with .status.
// 422 also carries .fields ({ field: [messages] }); other errors use the
// server's { error } text as the message when there is one.
export async function api(path, method = 'GET', body) {
  let res
  try {
    res = await fetch(path, {
      method,
      headers: { 'Content-Type': 'application/json' },
      body: body && JSON.stringify(body),
    })
  } catch {
    // fetch only throws when no response arrived; its own text ("Failed to fetch") means nothing to a customer.
    throw Object.assign(new Error("The server didn't respond. Check your connection and try again."), { status: 0 })
  }
  const data = await res.json().catch(() => null)
  if (res.ok) return data
  const fallback = res.status >= 500
    ? `Something went wrong on the server (${res.status}). Please try again.`
    : `Request failed (${res.status})`
  const err = new Error(data?.error ?? fallback)
  err.status = res.status
  if (res.status === 422) err.fields = data ?? {}
  throw err
}

// { pickup_date: ["can't be in the past"] } -> ["Pickup date can't be in the past"]
export function errorMessages(fields) {
  return Object.entries(fields).flatMap(([field, messages]) => {
    const name = field.replaceAll('_', ' ')
    const label = name.charAt(0).toUpperCase() + name.slice(1)
    return messages.map(message => `${label} ${message}`)
  })
}

export function errorText(err) {
  return err.fields ? errorMessages(err.fields).join('. ') : err.message
}

// Textarea -> list. The server still trims, uppercases and validates.
export function parseSerials(text) {
  return text.split('\n').map(line => line.trim()).filter(Boolean)
}

// Fallback only: the app uses GET /customer `today` (the server's Eastern date). toISOString() would use UTC.
export function todayLocal(now = new Date()) {
  const pad = n => String(n).padStart(2, '0')
  return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`
}

// "2026-11-03" -> "Nov 3, 2026". Built from parts so the timezone can't shift the day.
export function formatDate(isoDate) {
  const [y, m, d] = isoDate.split('-').map(Number)
  return new Date(y, m - 1, d).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric' })
}

export function formatDateTime(iso) {
  return new Date(iso).toLocaleString('en-US', {
    month: 'short', day: 'numeric', year: 'numeric', hour: 'numeric', minute: '2-digit',
  })
}

// Insert or replace one pickup, keeping the server's order (newest date first).
export function upsertPickup(list, pickup) {
  const rest = list.filter(p => p.id !== pickup.id)
  return [...rest, pickup].sort((a, b) => b.pickup_date.localeCompare(a.pickup_date) || b.id - a.id)
}

// Repurposed = resold + donated, out of devices that have an outcome. percent is null with no outcomes yet.
export function repurposeSummary(pickups) {
  const sum = key => pickups.reduce((n, p) => n + p.device_counts[key], 0)
  const donated = sum('donated')
  const repurposed = sum('resold') + donated
  const withOutcome = repurposed + sum('recycled')
  return { repurposed, donated, withOutcome, percent: withOutcome ? Math.round((repurposed / withOutcome) * 100) : null }
}

// `today` is the server's date from GET /customer. ISO date strings compare as dates.
export const isLate = (pickup, today) => pickup.status === 'scheduled' && pickup.pickup_date < today
export const canCollect = (pickup, today) => pickup.status === 'scheduled' && pickup.pickup_date <= today

// Devices that physically reached Revivn: not still expected, not marked never arrived.
export const checkedInCount = c => c.total - c.expected - (c.not_received ?? 0)
export const sanitizedCount = c => c.sanitized + c.resold + c.donated + c.recycled

// Found at intake: its history never had an `expected` step (it wasn't on the customer's list).
export const isUnlisted = device => Boolean(device.history?.length) && !device.history.some(e => e.status === 'expected')

// Arrived vs. the customer's estimate, once collected. "Fewer" waits until no listed device is still expected.
export function mismatchNote(pickup) {
  if (pickup.status !== 'collected') return null
  const diff = checkedInCount(pickup.device_counts) - pickup.estimated_device_count
  const noun = n => (n === 1 ? 'device' : 'devices')
  if (diff > 0) return `${diff} more ${noun(diff)} than you estimated.`
  if (diff < 0 && pickup.device_counts.expected === 0) return `${-diff} fewer ${noun(-diff)} than you estimated.`
  return null
}
