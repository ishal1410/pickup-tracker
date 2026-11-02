import { test } from 'node:test'
import assert from 'node:assert/strict'
import { api, errorMessages, errorText, formatDate, parseSerials, todayLocal, upsertPickup } from './lib.js'

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
