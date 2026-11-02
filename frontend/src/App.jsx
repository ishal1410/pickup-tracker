import { useEffect, useState } from 'react'
import { api, DEVICE_LABELS, errorText, formatDate, PROGRESS_LABELS, todayLocal, upsertPickup } from './lib.js'
import BookingForm from './BookingForm.jsx'
import PickupDetail from './PickupDetail.jsx'
import WarehousePanel from './WarehousePanel.jsx'
import Certificate from './Certificate.jsx'

const DEVICE_STATUSES = Object.keys(DEVICE_LABELS)

// Focus the first of these ids that exists, after React has painted.
// ponytail: ids + requestAnimationFrame instead of a ref per row.
function focusById(...ids) {
  requestAnimationFrame(() => {
    for (const id of ids) {
      const el = document.getElementById(id)
      if (el) {
        el.focus()
        return
      }
    }
  })
}

export default function App() {
  const [customer, setCustomer] = useState(null)
  const [pickups, setPickups] = useState([])
  const [loading, setLoading] = useState(true)
  const [loadError, setLoadError] = useState(null)
  const [reloadKey, setReloadKey] = useState(0)
  const [selected, setSelected] = useState(null) // pickup detail, with devices
  const [certificateId, setCertificateId] = useState(null)
  const [rowError, setRowError] = useState(null) // { key, message }, shown next to the control that failed
  const [notice, setNotice] = useState('')

  useEffect(() => {
    let ignore = false // a slow, outdated response must not overwrite a newer one
    setLoading(true)
    setLoadError(null)
    Promise.all([api('/customer'), api('/pickups')])
      .then(([me, list]) => {
        if (!ignore) {
          setCustomer(me)
          setPickups(list)
        }
      })
      .catch(() => { if (!ignore) setLoadError("Couldn't load your pickups. Please try again in a moment.") })
      .finally(() => { if (!ignore) setLoading(false) })
    return () => { ignore = true }
  }, [reloadKey])

  // The server says this pickup is gone (404): drop it instead of showing a ghost row.
  function forget(id) {
    setPickups(prev => prev.filter(p => p.id !== id))
    setSelected(prev => (prev?.id === id ? null : prev))
    setNotice('That pickup no longer exists.')
    focusById('pickups-heading') // its View button is gone, so focus would fall to the page top
  }

  async function openPickup(id) {
    setRowError(null)
    setCertificateId(null)
    try {
      const detail = await api(`/pickups/${id}`)
      setSelected(detail)
      setPickups(prev => upsertPickup(prev, detail))
      focusById('detail-heading')
    } catch (err) {
      if (err.status === 404) forget(id)
      else setRowError({ key: `list-${id}`, message: errorText(err) })
    }
  }

  // After a failed action the screen may be stale (another tab changed it), so refetch.
  async function refresh(id) {
    try {
      const detail = await api(`/pickups/${id}`)
      setPickups(prev => upsertPickup(prev, detail))
      setSelected(prev => (prev?.id === id ? detail : prev))
    } catch (err) {
      if (err.status === 404) forget(id)
    }
  }

  // Every action endpoint returns the whole pickup (API-v2 section 1), so one
  // success path keeps the list row and the open panel in sync.
  async function runAction({ key, pickupId, path, body, confirmText, focusIds = [] }) {
    if (confirmText && !window.confirm(confirmText)) return false
    setRowError(null)
    try {
      const updated = await api(path, 'POST', body)
      setPickups(prev => upsertPickup(prev, updated))
      setSelected(prev => (prev?.id === updated.id ? updated : prev))
      return true
    } catch (err) {
      setRowError({ key, message: errorText(err) })
      await refresh(pickupId)
      return false
    } finally {
      focusById(...focusIds, 'detail-heading')
    }
  }

  function handleBooked(pickup) {
    setPickups(prev => upsertPickup(prev, pickup))
    setSelected(pickup)
    setCertificateId(null)
    setRowError(null)
    const n = pickup.device_counts.total
    setNotice(`Pickup booked for ${formatDate(pickup.pickup_date)}${n ? ` with ${n} serial number${n === 1 ? '' : 's'}` : ''}.`)
    focusById('detail-heading')
  }

  // Totals across this customer's pickups, from data we already have.
  const totals = Object.fromEntries(
    DEVICE_STATUSES.map(s => [s, pickups.reduce((sum, p) => sum + p.device_counts[s], 0)]),
  )
  const allDevices = pickups.reduce((sum, p) => sum + p.device_counts.total, 0)
  const checkedIn = allDevices - totals.expected
  const sanitized = totals.sanitized + totals.resold + totals.donated + totals.recycled
  const activePickups = pickups.filter(p => p.status !== 'cancelled').length
  const figure = n => (loadError || loading ? '—' : n) // never show zeros we didn't load
  const today = todayLocal()

  return (
    <div className="page">
      <header className="topbar">
        <div className="product"><span className="brand-mark" aria-hidden="true" />Pickup Tracker</div>
        <p className="account">Account: <strong>{customer?.name ?? '…'}</strong></p>
      </header>

      <main>
        <div className="intro">
          <h1>Hardware pickups</h1>
          <p className="lede">Book pickups, follow every device through data sanitization, and get a certificate when it's done.</p>
        </div>

        {loadError && (
          <div className="banner" role="alert">
            <p>{loadError}</p>
            <button type="button" className="btn btn-quiet" onClick={() => setReloadKey(k => k + 1)}>Retry</button>
          </div>
        )}
        {/* The live region stays mounted so screen readers announce each new message. */}
        <div role="status">
          {notice && (
            <div className="notice">
              <p>{notice}</p>
              <button type="button" className="btn btn-quiet" onClick={() => setNotice('')}>Dismiss</button>
            </div>
          )}
        </div>

        <section className="summary" aria-label="Summary">
          <div className="totals">
            <div><p className="figure">{figure(activePickups)}</p><p className="figure-label">Pickups</p></div>
            <div><p className="figure">{figure(checkedIn)}</p><p className="figure-label">Devices checked in</p></div>
            <div><p className="figure">{figure(sanitized)}</p><p className="figure-label">Data sanitized</p></div>
          </div>
          <div className="pipeline">
            <p className="pipeline-title">Devices by status</p>
            <div className="pipeline-bar" aria-hidden="true">
              {DEVICE_STATUSES.map(s => totals[s] > 0 && (
                <span key={s} className={`segment tone-${s}`} style={{ flexGrow: totals[s] }} />
              ))}
            </div>
            <ul className="legend">
              {DEVICE_STATUSES.map(s => (
                <li key={s}>
                  <span className={`dot tone-${s}`} aria-hidden="true" />
                  <span className="legend-name">{DEVICE_LABELS[s]}</span>
                  <span className="legend-count">{figure(totals[s])}</span>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <div className="workspace">
          <BookingForm disabled={Boolean(loadError) || loading} onBooked={handleBooked} />

          <section className="shell" aria-labelledby="pickups-heading">
            <div className="core list">
              <h2 id="pickups-heading" tabIndex={-1}>Your pickups</h2>

              {loading && <p className="state">Loading pickups…</p>}
              {!loading && loadError && pickups.length === 0 && <p className="state">Your pickups will appear here once they load.</p>}
              {!loading && !loadError && pickups.length === 0 && (
                <p className="state">No pickups yet. Book the first one with the form.</p>
              )}

              {!loading && pickups.length > 0 && (
                <table>
                  <caption className="visually-hidden">Your pickups, newest date first</caption>
                  <thead>
                    <tr>
                      <th scope="col">Pickup date</th>
                      <th scope="col">Devices</th>
                      <th scope="col">Progress</th>
                      <th scope="col"><span className="visually-hidden">Actions</span></th>
                    </tr>
                  </thead>
                  <tbody>
                    {pickups.map(p => {
                      const isOpen = selected?.id === p.id
                      const late = p.status === 'scheduled' && p.pickup_date < today // ISO strings compare as dates
                      return (
                        <tr key={p.id} className={isOpen ? 'selected' : undefined} aria-current={isOpen ? 'true' : undefined}>
                          <td className="date">
                            {formatDate(p.pickup_date)}
                            {late && <span className="flag">Past pickup date, not collected yet</span>}
                          </td>
                          <td data-label="Devices">
                            {p.device_counts.total - p.device_counts.expected} checked in (est. {p.estimated_device_count})
                          </td>
                          <td><span className={`pill tone-${p.progress}`}>{PROGRESS_LABELS[p.progress]}</span></td>
                          <td className="actions">
                            <button type="button" className="btn btn-secondary" onClick={() => openPickup(p.id)}
                              aria-label={`View pickup on ${formatDate(p.pickup_date)}`}>
                              View
                            </button>
                            {rowError?.key === `list-${p.id}` && <p className="row-error" role="alert">{rowError.message}</p>}
                          </td>
                        </tr>
                      )
                    })}
                  </tbody>
                </table>
              )}
            </div>
          </section>
        </div>

        {selected && (
          <div className="detail-grid">
            <PickupDetail
              pickup={selected}
              rowError={rowError}
              onCancel={() => runAction({
                key: `pickup-${selected.id}`,
                pickupId: selected.id,
                path: `/pickups/${selected.id}/cancel`,
                confirmText: `Cancel the pickup on ${formatDate(selected.pickup_date)}? This can't be undone.`,
                focusIds: ['detail-heading'],
              })}
              onShowCertificate={() => setCertificateId(selected.id)}
            />
            <WarehousePanel pickup={selected} rowError={rowError} onAction={runAction} />
          </div>
        )}

        {certificateId && (
          <Certificate
            // Refetch when a warehouse step changes this pickup's devices while it's open,
            // so an outcome never shows as "Awaiting outcome" after it was recorded.
            key={certificateId}
            version={selected?.id === certificateId ? Object.values(selected.device_counts).join() : ''}
            pickupId={certificateId}
            onClose={() => {
              setCertificateId(null)
              focusById('detail-heading')
            }}
          />
        )}
      </main>
    </div>
  )
}
