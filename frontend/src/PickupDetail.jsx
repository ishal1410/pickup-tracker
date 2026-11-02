import { DEVICE_LABELS, formatDate, formatDateTime, METHOD_LABELS, PROGRESS_LABELS } from './lib.js'

const STEPS = ['scheduled', 'collected', 'processing', 'complete']

// The customer's read-only view of one pickup. Their only action is Cancel,
// and only while the pickup is scheduled.
export default function PickupDetail({ pickup, rowError, onCancel, onShowCertificate }) {
  const c = pickup.device_counts
  const sanitized = c.sanitized + c.resold + c.donated + c.recycled
  const current = STEPS.indexOf(pickup.progress)

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
          {c.total > 0 && ` ${c.total - c.expected} checked in, ${sanitized} of ${c.total} sanitized.`}
        </p>

        {/* A cancelled pickup never reaches Revivn, so it never gets a certificate. */}
        {pickup.status !== 'cancelled' && (
          <div className="detail-actions">
            <button type="button" className="btn btn-secondary" disabled={!pickup.certificate_available}
              aria-describedby={pickup.certificate_available ? undefined : 'cert-hint'} onClick={onShowCertificate}>
              View certificate of data destruction
            </button>
            {pickup.status === 'scheduled' && (
              <button type="button" className="btn btn-secondary btn-danger" onClick={onCancel}>Cancel pickup</button>
            )}
          </div>
        )}
        {pickup.status !== 'cancelled' && !pickup.certificate_available && (
          <p id="cert-hint" className="hint">
            {c.total === 0
              ? 'The certificate is ready once devices are checked in and every one is sanitized.'
              : `The certificate is ready once every device is sanitized (${sanitized} of ${c.total} so far).`}
          </p>
        )}
        {rowError?.key === `pickup-${pickup.id}` && <p className="row-error" role="alert">{rowError.message}</p>}

        {pickup.devices.length === 0 ? (
          <p className="state">No devices listed yet. Revivn records each serial number when the devices arrive.</p>
        ) : (
          <table className="devices">
            <caption className="visually-hidden">Devices in this pickup</caption>
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
                  <th scope="row" className="serial">{d.serial_number}</th>
                  <td data-label="Model">{d.model || 'Not recorded'}</td>
                  <td><span className={`pill tone-${d.status}`}>{DEVICE_LABELS[d.status]}</span></td>
                  <td data-label="Sanitized">
                    {d.sanitized_at ? `${METHOD_LABELS[d.sanitization_method]}, ${formatDateTime(d.sanitized_at)}` : 'Not yet'}
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
