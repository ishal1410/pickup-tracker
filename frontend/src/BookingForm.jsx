import { useState } from 'react'
import { api, errorMessages, parseSerials, todayLocal } from './lib.js'

const EMPTY = { pickup_date: '', estimated_device_count: '', serials: '' }

export default function BookingForm({ disabled, onBooked }) {
  const [form, setForm] = useState(EMPTY)
  const [fieldErrors, setFieldErrors] = useState({})
  const [formError, setFormError] = useState(null)
  const [saving, setSaving] = useState(false)
  const serialCount = parseSerials(form.serials).length

  function update(field, value) {
    setForm(prev => ({ ...prev, [field]: value }))
  }

  async function submit(e) {
    e.preventDefault()
    setSaving(true)
    setFormError(null)
    try {
      const pickup = await api('/pickups', 'POST', {
        pickup: {
          pickup_date: form.pickup_date,
          estimated_device_count: form.estimated_device_count,
          serial_numbers: parseSerials(form.serials),
        },
      })
      setForm(EMPTY)
      setFieldErrors({})
      onBooked(pickup)
    } catch (err) {
      // 422: errors go under each field and the values stay. Anything else: one message by the button.
      setFieldErrors(err.fields ?? {})
      if (err.fields) {
        // Move focus to the first field that failed, in form order (the server's key order
        // follows its validations), so its error is read out.
        const first = ['pickup_date', 'estimated_device_count', 'serial_numbers'].find(f => err.fields[f])
        document.getElementById(first === 'serial_numbers' ? 'serials' : first)?.focus()
      } else {
        setFormError(`Couldn't book the pickup. ${err.message}`)
      }
    } finally {
      setSaving(false)
    }
  }

  // "Pickup date can't be in the past", under its own input.
  function errorFor(field) {
    if (!fieldErrors[field]) return null
    return <p id={`${field}-error`} className="field-error">{errorMessages({ [field]: fieldErrors[field] }).join('. ')}</p>
  }

  function describedBy(field, hintId) {
    return [hintId, fieldErrors[field] && `${field}-error`].filter(Boolean).join(' ') || undefined
  }

  return (
    <section className="shell" aria-labelledby="book-heading">
      <form className="core form" onSubmit={submit} noValidate>
        <h2 id="book-heading">Book a pickup</h2>

        <div className="field">
          <label htmlFor="pickup_date">Pickup date</label>
          <input id="pickup_date" type="date" min={todayLocal()} value={form.pickup_date} required
            onChange={e => update('pickup_date', e.target.value)}
            aria-invalid={Boolean(fieldErrors.pickup_date)} aria-describedby={describedBy('pickup_date')} />
          {errorFor('pickup_date')}
        </div>

        <div className="field">
          <label htmlFor="estimated_device_count">Estimated number of devices</label>
          <input id="estimated_device_count" type="number" min="1" max="10000" step="1" inputMode="numeric" required
            value={form.estimated_device_count} onChange={e => update('estimated_device_count', e.target.value)}
            aria-invalid={Boolean(fieldErrors.estimated_device_count)}
            aria-describedby={describedBy('estimated_device_count', 'estimate-hint')} />
          <p id="estimate-hint" className="hint">A rough count is fine, up to 10,000.</p>
          {errorFor('estimated_device_count')}
        </div>

        <div className="field">
          <label htmlFor="serials">Serial numbers (optional)</label>
          <textarea id="serials" rows={5} spellCheck={false} value={form.serials}
            onChange={e => update('serials', e.target.value)}
            aria-invalid={Boolean(fieldErrors.serial_numbers)}
            aria-describedby={describedBy('serial_numbers', 'serials-hint')} />
          <p id="serials-hint" className="hint">
            One per line ({serialCount} listed). Leave it blank and Revivn records serials when the devices arrive.
          </p>
          {fieldErrors.serial_numbers && (
            <ul id="serial_numbers-error" className="field-error">
              {fieldErrors.serial_numbers.map(message => <li key={message}>{message}</li>)}
            </ul>
          )}
        </div>

        {formError && <p className="field-error" role="alert">{formError}</p>}
        <button className="btn btn-primary" disabled={saving || disabled}>{saving ? 'Booking…' : 'Book pickup'}</button>
        {disabled && <p className="hint">Booking is paused until your pickups load.</p>}
      </form>
    </section>
  )
}
