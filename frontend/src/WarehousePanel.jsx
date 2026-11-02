import { useState } from 'react'
import { DEVICE_LABELS } from './lib.js'

const TERMINAL = ['resold', 'donated', 'recycled']

// DEMO ONLY. In production these steps come from Revivn's warehouse tools,
// never from the customer's screen. The panel exists so the read-only
// customer view can be shown updating live.
export default function WarehousePanel({ pickup, rowError, onAction }) {
  const [serial, setSerial] = useState('')
  const [model, setModel] = useState('')
  const openDevices = pickup.devices.filter(d => !TERMINAL.includes(d.status))
  const errorFor = key => rowError?.key === key && <p className="row-error" role="alert">{rowError.message}</p>

  // Collect, receive and check-in record a physical fact, so no confirm.
  // Sanitize and dispose are irreversible decisions, so they confirm first.
  function deviceAction(device, action, body, confirmText) {
    return onAction({
      key: `device-${device.id}`,
      pickupId: pickup.id,
      path: `/devices/${device.id}/${action}`,
      body,
      confirmText,
      focusIds: [`wh-device-${device.id}`, 'warehouse-heading'],
    })
  }

  function dispose(device, outcome, label) {
    return deviceAction(device, 'dispose', { outcome }, `Mark ${device.serial_number} as ${label}? This is final.`)
  }

  async function addDevice(e) {
    e.preventDefault()
    const ok = await onAction({
      key: 'add-device',
      pickupId: pickup.id,
      path: `/pickups/${pickup.id}/devices`,
      body: { device: { serial_number: serial, model } },
      focusIds: ['wh-serial'],
    })
    if (ok) {
      setSerial('')
      setModel('')
    }
  }

  return (
    <section className="shell simulator" aria-labelledby="warehouse-heading">
      <div className="core">
        <p className="demo-tag">Demo only</p>
        <h2 id="warehouse-heading" tabIndex={-1}>Warehouse simulator (demo)</h2>
        <p className="hint">
          Customers can't do any of this. In production, Revivn's warehouse team records these steps.
          They're here so you can watch the customer view update.
        </p>

        {pickup.status === 'cancelled' && <p className="state">This pickup was cancelled. Nothing to simulate.</p>}

        {pickup.status === 'scheduled' && (
          <>
            <div className="detail-actions">
              <button type="button" className="btn btn-secondary"
                onClick={() => onAction({ key: 'collect', pickupId: pickup.id, path: `/pickups/${pickup.id}/collect`, focusIds: ['warehouse-heading'] })}>
                Mark pickup collected
              </button>
            </div>
            {errorFor('collect')}
          </>
        )}

        {pickup.status === 'collected' && (
          <>
            <form className="add-device" onSubmit={addDevice}>
              <div className="field">
                <label htmlFor="wh-serial">Unlisted device: serial number</label>
                <input id="wh-serial" value={serial} maxLength={50} spellCheck={false} onChange={e => setSerial(e.target.value)}
                  aria-invalid={rowError?.key === 'add-device'} aria-describedby={rowError?.key === 'add-device' ? 'add-device-error' : undefined} />
              </div>
              <div className="field">
                <label htmlFor="wh-model">Model (optional)</label>
                <input id="wh-model" value={model} maxLength={100} onChange={e => setModel(e.target.value)} />
              </div>
              <button className="btn btn-secondary">Check in device</button>
            </form>
            {rowError?.key === 'add-device' && <p id="add-device-error" className="row-error" role="alert">{rowError.message}</p>}

            {openDevices.length === 0 ? (
              <p className="state">No devices waiting for a step.</p>
            ) : (
              <table className="devices">
                <caption className="visually-hidden">Devices waiting for a warehouse step</caption>
                <thead>
                  <tr>
                    <th scope="col">Serial number</th>
                    <th scope="col">Status</th>
                    <th scope="col">Next step</th>
                  </tr>
                </thead>
                <tbody>
                  {openDevices.map(d => (
                    <tr key={d.id}>
                      <th scope="row" id={`wh-device-${d.id}`} tabIndex={-1} className="serial">{d.serial_number}</th>
                      <td><span className={`pill tone-${d.status}`}>{DEVICE_LABELS[d.status]}</span></td>
                      <td className="step-actions">
                        {d.status === 'expected' && (
                          <button type="button" className="btn btn-secondary" onClick={() => deviceAction(d, 'receive')}>Receive</button>
                        )}
                        {d.status === 'received' && (
                          <>
                            <button type="button" className="btn btn-secondary"
                              onClick={() => deviceAction(d, 'sanitize', { sanitization_method: 'wipe' }, `Wipe the data on ${d.serial_number}? This can't be undone.`)}>
                              Sanitize: wipe
                            </button>
                            <button type="button" className="btn btn-secondary"
                              onClick={() => deviceAction(d, 'sanitize', { sanitization_method: 'destroy' }, `Destroy the drive in ${d.serial_number}? It can then only be recycled.`)}>
                              Sanitize: destroy
                            </button>
                          </>
                        )}
                        {d.status === 'sanitized' && (
                          <>
                            {d.sanitization_method === 'wipe' && (
                              <>
                                <button type="button" className="btn btn-secondary" onClick={() => dispose(d, 'resold', 'resold')}>Resell</button>
                                <button type="button" className="btn btn-secondary" onClick={() => dispose(d, 'donated', 'donated')}>Donate</button>
                              </>
                            )}
                            <button type="button" className="btn btn-secondary" onClick={() => dispose(d, 'recycled', 'recycled')}>Recycle</button>
                          </>
                        )}
                        {errorFor(`device-${d.id}`)}
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </>
        )}
      </div>
    </section>
  )
}
