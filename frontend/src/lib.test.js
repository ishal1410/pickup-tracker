import { test } from 'node:test'
import assert from 'node:assert/strict'
import {
  api, canCollect, checkedInCount, errorMessages, errorText, formatDate, isLate, isUnlisted, mismatchNote,
  parseSerials, repurposeSummary, sanitizedCount, todayLocal, upsertPickup,
} from './lib.js'

test('errorMessages turns Rails keys into sentences', () => {
  assert.deepEqual(
    errorMessages({ status: ["can't go from received to resold"], pickup_date: ["can't be in the past"] }),
    ["Status can't go from received to resold", "Pickup date can't be in the past"],
  )
})

test('errorText prefers field messages, then the plain message', () => {
  const fieldErr = Object.assign(new Error('x'), { fields: { pickup: ['must be collected first'] } })
  assert.equal(errorText(fieldErr), 'Pickup must be collected first')
  assert.equal(errorText(new Error('Pickup not found')), 'Pickup not found')
})

test('parseSerials trims and drops blank lines', () => {
  assert.deepEqual(parseSerials(' C02A \n\n  c02b\n   '), ['C02A', 'c02b'])
  assert.deepEqual(parseSerials(''), [])
})

test('todayLocal uses local date parts, not UTC', () => {
  assert.equal(todayLocal(new Date(2026, 10, 1, 23, 59)), '2026-11-01')
})

test('formatDate never shifts the day', () => {
  assert.equal(formatDate('2026-11-03'), 'Nov 3, 2026')
})

test('upsertPickup replaces by id and keeps newest date first', () => {
  const list = [{ id: 1, pickup_date: '2026-11-07' }, { id: 2, pickup_date: '2026-10-11' }]
  const replaced = upsertPickup(list, { id: 2, pickup_date: '2026-10-11', progress: 'complete' })
  assert.equal(replaced.find(p => p.id === 2).progress, 'complete')
  const inserted = upsertPickup(list, { id: 3, pickup_date: '2026-11-01' })
  assert.deepEqual(inserted.map(p => p.id), [1, 3, 2])
})

test('api returns parsed JSON on success', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ id: 1 }), { status: 200 })
  assert.deepEqual(await api('/customer'), { id: 1 })
})

test('api puts 422 field errors on err.fields', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ status: ['bad'] }), { status: 422 })
  await assert.rejects(api('/x', 'POST', {}), err => err.status === 422 && err.fields.status[0] === 'bad')
})

test('api uses the server error message on 409', async () => {
  globalThis.fetch = async () => new Response(JSON.stringify({ error: 'Certificate is available once every device in this pickup is sanitized' }), { status: 409 })
  await assert.rejects(api('/pickups/1/certificate'), err => err.status === 409 && err.message.startsWith('Certificate is available'))
})

test('api survives a non-JSON error body', async () => {
  globalThis.fetch = async () => new Response('Not Found', { status: 404 })
  await assert.rejects(api('/nope'), err => err.status === 404 && err.message === 'Request failed (404)')
})

// Regression: gstack-qa-v2 ISSUE-005. Users saw the raw "Failed to fetch" and "Request failed (500)".
test('api turns a network failure into a plain sentence', async () => {
  globalThis.fetch = async () => { throw new TypeError('Failed to fetch') }
  await assert.rejects(api('/pickups'), err => err.status === 0 && err.message === "The server didn't respond. Check your connection and try again.")
})

test('api explains a 5xx without a JSON body', async () => {
  globalThis.fetch = async () => new Response('boom', { status: 500 })
  await assert.rejects(api('/pickups/1'), err => err.status === 500 && err.message === 'Something went wrong on the server (500). Please try again.')
})

test('repurposeSummary counts resold + donated out of devices with an outcome', () => {
  const counts = (resold, donated, recycled) => ({ device_counts: { resold, donated, recycled, sanitized: 4 } })
  assert.deepEqual(repurposeSummary([counts(3, 1, 1), counts(1, 1, 1)]), { repurposed: 6, donated: 2, withOutcome: 8, percent: 75 })
  assert.equal(repurposeSummary([counts(1, 0, 2)]).percent, 33) // rounded
})

test('repurposeSummary has no percent when nothing has an outcome yet', () => {
  assert.deepEqual(repurposeSummary([]), { repurposed: 0, donated: 0, withOutcome: 0, percent: null })
})

test('api sends JSON with a Content-Type header (demo reset answers 415 without it)', async () => {
  let seen
  globalThis.fetch = async (path, init) => { seen = init; return new Response('{}', { status: 200 }) }
  await api('/demo/reset', 'POST', { sample: true })
  assert.equal(seen.headers['Content-Type'], 'application/json')
  assert.equal(seen.body, '{"sample":true}')
})

// Server "today" (GET /customer), not the browser's date: bug-hunt BUG-2 / BUG-6.
test('isLate: scheduled and dated before server today', () => {
  assert.equal(isLate({ status: 'scheduled', pickup_date: '2026-11-01' }, '2026-11-02'), true)
  assert.equal(isLate({ status: 'scheduled', pickup_date: '2026-11-02' }, '2026-11-02'), false)
  assert.equal(isLate({ status: 'collected', pickup_date: '2026-10-01' }, '2026-11-02'), false)
})

test('canCollect: scheduled and dated today or earlier', () => {
  assert.equal(canCollect({ status: 'scheduled', pickup_date: '2026-11-02' }, '2026-11-02'), true)
  assert.equal(canCollect({ status: 'scheduled', pickup_date: '2026-11-03' }, '2026-11-02'), false)
  assert.equal(canCollect({ status: 'cancelled', pickup_date: '2026-11-01' }, '2026-11-02'), false)
})

const counts = over => ({ expected: 0, received: 0, sanitized: 0, resold: 0, donated: 0, recycled: 0, not_received: 0, total: 0, ...over })

test('checkedInCount leaves out expected and not received devices', () => {
  assert.equal(checkedInCount(counts({ expected: 1, received: 2, not_received: 1, total: 4 })), 2)
  assert.equal(checkedInCount({ expected: 1, total: 3 }), 2) // older shape without not_received
})

test('sanitizedCount is sanitized plus every outcome', () => {
  assert.equal(sanitizedCount(counts({ sanitized: 1, resold: 2, donated: 1, recycled: 3, received: 5 })), 7)
})

test('isUnlisted: a device whose history never had expected was added at intake', () => {
  assert.equal(isUnlisted({ history: [{ status: 'received', at: 'x' }, { status: 'sanitized', at: 'y' }] }), true)
  assert.equal(isUnlisted({ history: [{ status: 'expected', at: 'x' }, { status: 'received', at: 'y' }] }), false)
  assert.equal(isUnlisted({ history: [] }), false)
  assert.equal(isUnlisted({}), false)
})

test('mismatchNote compares devices checked in with the estimate, only after collect', () => {
  const pickup = (status, estimated_device_count, c) => ({ status, estimated_device_count, device_counts: counts(c) })
  assert.equal(mismatchNote(pickup('collected', 3, { received: 4, total: 4 })), '1 more device than you estimated.')
  assert.equal(mismatchNote(pickup('collected', 5, { received: 2, not_received: 1, total: 3 })), '3 fewer devices than you estimated.')
  assert.equal(mismatchNote(pickup('collected', 3, { received: 3, total: 3 })), null)
  // Still waiting on listed devices: "fewer" isn't known yet.
  assert.equal(mismatchNote(pickup('collected', 3, { received: 1, expected: 2, total: 3 })), null)
  assert.equal(mismatchNote(pickup('scheduled', 3, { expected: 5, total: 5 })), null)
})
