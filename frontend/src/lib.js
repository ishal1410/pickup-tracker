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

// Today in the browser's timezone. toISOString() would use UTC.
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
