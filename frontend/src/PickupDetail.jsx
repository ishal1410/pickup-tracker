import {
  checkedInCount, DEVICE_LABELS, formatDate, formatDateTime, isUnlisted, METHOD_LABELS, mismatchNote, PROGRESS_LABELS,
  sanitizedCount,
} from './lib.js'

const STEPS = ['scheduled', 'collected', 'processing', 'complete']

// The customer's read-only view of one pickup. Their only action is Cancel,
// and only while the pickup is scheduled.
export default function PickupDetail({ pickup, rowError, busy, onCancel, onShowCertificate }) {
  const c = pickup.device_counts
  const notReceived = c.not_received ?? 0
  const sanitized = sanitizedCount(c)
  const arrived = c.total - notReceived // devices that are, or will be, at Revivn
  const current = STEPS.indexOf(pickup.progress)
  const mismatch = mismatchNote(pickup)

  return (
    <section className="shell" aria-labelledby="detail-heading">
      <div className="core">
        <h2 id="detail-heading" tabIndex={-1}>Pickup on {formatDate(pickup.pickup_date)}</h2>

        {pickup.progress === 'cancelled' ? (
          <p><span className="pill tone-cancelled">Cancelled</span></p>
        ) : (
          <ol className="progress" aria-label="Progress">
            {STEPS.map((step, i) => (
              <li key={step} className={i <= current ? 'done' : undefined} aria-current={i === current ? 'step' : undefined}>
                {PROGRESS_LABELS[step]}
              </li>
            ))}
          </ol>
        )}

        <p className="hint">
          You estimated {pickup.estimated_device_count}.
          {arrived > 0 && ` ${checkedInCount(c)} checked in, ${sanitized} of ${arrived} sanitized.`}
          {mismatch && <strong className="mismatch"> {mismatch}</strong>}
          {/* Cancelling releases listed serials as not received (so they can be rebooked); that isn't news here. */}
          {notReceived > 0 && pickup.status === 'collected' && ` ${notReceived} listed ${notReceived === 1 ? 'device was' : 'devices were'} not received.`}
        </p>
        {pickup.certificate_number && (
          <p className="hint">Certificate {pickup.certificate_number} issued. This pickup is closed to new devices.</p>
        )}

        {/* A cancelled pickup never reaches Revivn, so it never gets a certificate. */}
        {pickup.status !== 'cancelled' && (
          <div className="detail-actions">
            <button type="button" className="btn btn-secondary" disabled={!pickup.certificate_available}
              aria-describedby={pickup.certificate_available ? undefined : 'cert-hint'} onClick={onShowCertificate}>
              View certificate of data destruction
            </button>
            {pickup.status === 'scheduled' && (
              <button type="button" className="btn btn-secondary btn-danger" disabled={busy} onClick={onCancel}>Cancel pickup</button>
            )}
          </div>
        )}
        {pickup.status !== 'cancelled' && !pickup.certificate_available && (
          <p id="cert-hint" className="hint">
            {c.total === 0
              ? 'The certificate is ready once devices are checked in and every one is sanitized.'
              : `The certificate is ready once no listed device is still expected and every device that arrived is sanitized (${sanitized} of ${arrived} so far).`}
          </p>
        )}
        {rowError?.key === `pickup-${pickup.id}` && <p className="row-error" role="alert">{rowError.message}</p>}

        {pickup.devices.length === 0 ? (
          <p className="state">No devices listed yet. Revivn records each serial number when the devices arrive.</p>
        ) : (
          <table className="devices">
            <caption className="visually-hidden">Devices in this pickup, each with its status history</caption>
            <thead>
              <tr>
                <th scope="col">Serial number</th>
                <th scope="col">Model</th>
                <th scope="col">Status</th>
                <th scope="col">Data sanitized</th>
              </tr>
            </thead>
            <tbody>
              {pickup.devices.map(d => (
                <tr key={d.id}>
                  <th scope="row" className="serial">
                    {d.serial_number}
                    {isUnlisted(d) && (
                      <span className="tag">Unlisted<span className="visually-hidden">: not on your booking list, found at intake</span></span>
                    )}
                  </th>
                  <td data-label="Model">{d.model || 'Not recorded'}</td>
                  <td>
                    <span className={`pill tone-${d.status}`}>{DEVICE_LABELS[d.status]}</span>
                    {d.history?.length > 0 && (
                      // Native disclosure: keyboard and screen reader support for free, rows stay compact.
                      <details className="history">
                        <summary>History<span className="visually-hidden"> of {d.serial_number}</span></summary>
                        <ol>
                          {d.history.map(e => (
                            <li key={`${e.status}-${e.at}`}>
                              {DEVICE_LABELS[e.status]} <time dateTime={e.at}>{formatDateTime(e.at)}</time>
                            </li>
                          ))}
                        </ol>
                      </details>
                    )}
                  </td>
                  <td data-label="Sanitized">
                    {d.sanitized_at ? `${METHOD_LABELS[d.sanitization_method]}, ${formatDateTime(d.sanitized_at)}` : d.status === 'not_received' ? 'Never arrived' : 'Not yet'}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </section>
  )
}
