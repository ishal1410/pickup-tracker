import { useEffect, useRef, useState } from 'react'
import {
  api, checkedInCount, DEVICE_LABELS, errorText, formatDate, isLate, PROGRESS_LABELS, repurposeSummary,
  sanitizedCount, todayLocal, upsertPickup,
} from './lib.js'
import BookingForm from './BookingForm.jsx'
import PickupDetail from './PickupDetail.jsx'
import WarehousePanel from './WarehousePanel.jsx'
import Certificate from './Certificate.jsx'

const DEVICE_STATUSES = Object.keys(DEVICE_LABELS)
// The headline "Data sanitized" counts outcomes too, so the legend names the no-outcome-yet bucket plainly.
const LEGEND_LABELS = { ...DEVICE_LABELS, sanitized: 'Awaiting outcome' }

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
  // ponytail: plain state, so every reload starts on the welcome card again (no storage, no router).
  const [entered, setEntered] = useState(false)
  const [resetting, setResetting] = useState(false)
  const [pending, setPending] = useState(false) // a warehouse or cancel action is in flight
  const inFlight = useRef(false) // the same flag, readable before React re-renders (a fast double click)
  // Bumped by each successful reset. A request that started under an older generation drops its answer,
  // so a slow detail response can't bring back a pickup the reset deleted.
  const generation = useRef(0)
  // Ids to focus after the next commit; the first that exists wins. Focus also scrolls it into view,
  // which on a phone brings the new pickup's detail up after booking.
  // ponytail: ids instead of a ref per row.
  const [focusIds, setFocusIds] = useState(null)
  const focusById = (...ids) => setFocusIds(ids)
  const busy = pending || resetting

  useEffect(() => {
    focusIds?.map(id => document.getElementById(id)).find(Boolean)?.focus()
  }, [focusIds])

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

  // The server says this pickup is gone (404): drop it, and its certificate, instead of showing a ghost.
  function forget(id) {
    setPickups(prev => prev.filter(p => p.id !== id))
    setSelected(prev => (prev?.id === id ? null : prev))
    setCertificateId(prev => (prev === id ? null : prev))
    setNotice('That pickup no longer exists.')
    focusById('pickups-heading') // its View button is gone, so focus would fall to the page top
  }

  async function openPickup(id) {
    setRowError(null)
    setCertificateId(null)
    const gen = generation.current
    try {
      const detail = await api(`/pickups/${id}`)
      if (gen !== generation.current) return
      setSelected(detail)
      setPickups(prev => upsertPickup(prev, detail))
      focusById('detail-heading')
    } catch (err) {
      if (gen !== generation.current) return
      if (err.status === 404) forget(id)
      else setRowError({ key: `list-${id}`, message: errorText(err) })
    }
  }

  // After a failed action the screen may be stale (another tab changed it), so refetch.
  // Also after the certificate loads: issuing it closes intake, so certificate_number changed.
  async function refresh(id) {
    const gen = generation.current
    try {
      const detail = await api(`/pickups/${id}`)
      if (gen !== generation.current) return
      setPickups(prev => upsertPickup(prev, detail))
      setSelected(prev => (prev?.id === id ? detail : prev))
    } catch (err) {
      if (gen === generation.current && err.status === 404) forget(id)
    }
  }

  // Every action endpoint returns the whole pickup (API-v2 section 1), so one
  // success path keeps the list row and the open panel in sync.
  // One request at a time: buttons are disabled while `busy`, and inFlight stops a second click that
  // lands before the re-render (it would get a false "can't go from received to received").
  async function runAction({ key, pickupId, path, body, confirmText, focusIds: ids = [] }) {
    if (inFlight.current) return false
    if (confirmText && !window.confirm(confirmText)) return false
    inFlight.current = true
    setPending(true)
    setRowError(null)
    const gen = generation.current
    try {
      const updated = await api(path, 'POST', body)
      if (gen !== generation.current) return false
      setPickups(prev => upsertPickup(prev, updated))
      setSelected(prev => (prev?.id === updated.id ? updated : prev))
      return true
    } catch (err) {
      if (gen !== generation.current) return false
      setRowError({ key, message: errorText(err) })
      await refresh(pickupId)
      return false
    } finally {
      inFlight.current = false
      setPending(false)
      if (gen === generation.current) focusById(...ids, 'detail-heading')
    }
  }

  // Demo only: wipe this customer's pickups on the server, optionally reloading the six samples.
  async function resetDemo(sample) {
    if (inFlight.current) return
    const account = customer?.name ?? 'this account'
    const question = sample
      ? `Load sample data? This replaces every pickup on ${account} with the 6 sample pickups.`
      : `Reset demo data? This deletes every pickup on ${account} and starts an empty account.`
    if (!window.confirm(question)) return
    inFlight.current = true
    setResetting(true)
    try {
      const result = await api('/demo/reset', 'POST', { sample })
      generation.current += 1 // the server's data is gone: drop every answer still on its way
      setSelected(null)
      setCertificateId(null)
      setRowError(null)
      setReloadKey(k => k + 1)
      const n = result.pickups_count
      setNotice(sample ? `Sample data loaded: ${n} pickup${n === 1 ? '' : 's'}.` : 'Demo data reset. The account has no pickups.')
    } catch (err) {
      // Two different 404s (API-v2 4.10): the guard answers "Not found", an unseeded database "Customer not found".
      setNotice(err.status === 404 && err.message === 'Not found'
        ? 'Demo controls are turned off on this server.'
        : `Couldn't reset the demo. ${errorText(err)}`)
    } finally {
      inFlight.current = false
      setResetting(false)
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
    DEVICE_STATUSES.map(s => [s, pickups.reduce((sum, p) => sum + (p.device_counts[s] ?? 0), 0)]),
  )
  const checkedIn = pickups.reduce((sum, p) => sum + checkedInCount(p.device_counts), 0)
  const sanitized = sanitizedCount(totals)
  const activePickups = pickups.filter(p => p.status !== 'cancelled').length
  const reuse = repurposeSummary(pickups)
  const figure = n => (loadError || loading ? '—' : n) // never show zeros we didn't load
  const today = customer?.today ?? todayLocal() // the server's date decides; the browser's is only a fallback
  const empty = !loading && !loadError && pickups.length === 0 // first run: guide, don't show zeros

  if (!entered) {
    return (
      <main className="welcome">
        <section className="shell welcome-card" aria-labelledby="welcome-heading">
          <div className="core">
            <span className="brand-mark" aria-hidden="true" />
            <h1 id="welcome-heading">Pickup Tracker</h1>
            <p className="welcome-sub">Revivn customer portal (demo)</p>
            <ol className="custody">
              <li>Book a pickup</li>
              <li>Track every serial number from pickup to resale, donation or recycling</li>
              <li>Get a certificate</li>
            </ol>
            <button type="button" className="btn btn-primary" onClick={() => {
              setEntered(true)
              focusById('portal-heading')
            }}>
              {customer ? `Continue as ${customer.name}` : 'Continue'}
            </button>
            <p className="hint welcome-note">Demo account, no login.</p>
          </div>
        </section>
      </main>
    )
  }

  return (
    <div className="page">
      <header className="topbar">
        <div className="product"><span className="brand-mark" aria-hidden="true" />Pickup Tracker</div>
        <div className="topbar-right">
          <p className="account">Account: <strong>{customer?.name ?? '…'}</strong></p>
          <div className="demo-controls" role="group" aria-labelledby="demo-label">
            <span id="demo-label">Demo:</span>
            <button type="button" className="btn btn-secondary btn-small" disabled={busy} onClick={() => resetDemo(true)}>Load sample data</button>
            <button type="button" className="btn btn-secondary btn-small" disabled={busy} onClick={() => resetDemo(false)}>Reset demo data</button>
          </div>
        </div>
      </header>

      <main>
        <div className="intro">
          <h1 id="portal-heading" tabIndex={-1}>Hardware pickups</h1>
          <p className="lede">Book pickups, follow every device through data sanitization to resale, donation or recycling, and get a certificate of data destruction.</p>
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

        {!empty && <section className="summary" aria-label="Summary">
          <div className="totals">
            <div><p className="figure">{figure(activePickups)}</p><p className="figure-label">Active pickups</p></div>
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
                  <span className="legend-name">{LEGEND_LABELS[s]}</span>
                  <span className="legend-count">{figure(totals[s])}</span>
                </li>
              ))}
            </ul>
          </div>
          <div className="repurpose">
            <p>
              <span className="repurpose-label">Repurposed:</span>{' '}
              {loadError || loading || reuse.percent === null
                ? <><span aria-hidden="true">—</span><span className="visually-hidden">no device outcomes yet</span></>
                : <><strong>{reuse.repurposed} of {reuse.withOutcome}</strong> devices with an outcome ({reuse.percent}%)</>}
            </p>
            <p>
              <span className="repurpose-label">Donated:</span>{' '}
              <strong>{figure(reuse.donated)}</strong> {reuse.donated === 1 ? 'device' : 'devices'}
              <span className="repurpose-note">Donated devices go to people who need computer access.</span>
            </p>
          </div>
        </section>}

        <div className="workspace">
          <BookingForm today={today} disabled={Boolean(loadError) || loading || resetting} onBooked={handleBooked} />

          <section className="shell" aria-labelledby="pickups-heading">
            <div className="core list">
              <h2 id="pickups-heading" tabIndex={-1}>Your pickups</h2>

              {loading && <p className="state">Loading pickups…</p>}
              {!loading && loadError && pickups.length === 0 && <p className="state">Your pickups will appear here once they load.</p>}
              {empty && (
                <div className="empty">
                  <p className="empty-title">No pickups yet. Book your first pickup.</p>
                  <p className="hint">Use the form to pick a date and add serial numbers. Each device is tracked until it's resold, donated or recycled.</p>
                  <button type="button" className="link-btn" disabled={busy} onClick={() => resetDemo(true)}>
                    or load sample data (6 pickups)
                  </button>
                </div>
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
                      return (
                        <tr key={p.id} className={isOpen ? 'selected' : undefined} aria-current={isOpen ? 'true' : undefined}>
                          <td className="date">
                            {formatDate(p.pickup_date)}
                            {isLate(p, today) && <span className="flag">Past pickup date, not collected yet</span>}
                          </td>
                          <td data-label="Devices">
                            {checkedInCount(p.device_counts)} checked in (est. {p.estimated_device_count})
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
              busy={busy}
              onCancel={() => runAction({
                key: `pickup-${selected.id}`,
                pickupId: selected.id,
                path: `/pickups/${selected.id}/cancel`,
                confirmText: `Cancel the pickup on ${formatDate(selected.pickup_date)}? This can't be undone.`,
                focusIds: ['detail-heading'],
              })}
              onShowCertificate={() => setCertificateId(selected.id)}
            />
            <WarehousePanel pickup={selected} today={today} busy={busy} rowError={rowError} onAction={runAction} />
          </div>
        )}

        {certificateId && (
          <Certificate
            // Refetch when a warehouse step changes this pickup's devices while it's open,
            // so an outcome never shows as "Awaiting outcome" after it was recorded.
            key={certificateId}
            version={selected?.id === certificateId ? Object.values(selected.device_counts).join() : ''}
            pickupId={certificateId}
            onLoaded={() => refresh(certificateId)}
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
