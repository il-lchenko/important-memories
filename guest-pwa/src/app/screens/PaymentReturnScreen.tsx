import { useEffect, useRef, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { hostApi, type EventOut } from '../api/hostClient'
import { clearPending, loadPending, type PendingPayment } from '../payments'
import { qk } from '../queries'
import { Spinner } from '../ui'

const MAX_TRIES = 20
const EVERY_MS = 3000

function succeeded(e: EventOut, p: PendingPayment): boolean {
  const x = p.expect
  if (x.status && e.status === x.status) return true
  if (x.expiresAfter && e.expires_at && new Date(e.expires_at) > new Date(x.expiresAfter)) return true
  if (x.maxGuests && e.settings.max_guests >= x.maxGuests) return true
  if (x.frames && e.settings.frames_per_guest >= x.frames) return true
  return false
}

type Phase = 'checking' | 'ok' | 'timeout' | 'unknown'

export default function PaymentReturnScreen() {
  const navigate = useNavigate()
  const qc = useQueryClient()
  const [params] = useSearchParams()
  const pending = useRef<PendingPayment | null>(loadPending())
  const eventId = pending.current?.eventId ?? params.get('event') ?? ''
  const [phase, setPhase] = useState<Phase>(pending.current ? 'checking' : 'unknown')
  const [tries, setTries] = useState(0)
  const [nonce, setNonce] = useState(0)

  useEffect(() => {
    const p = pending.current
    if (!p || phase !== 'checking') return
    let stopped = false
    let n = 0
    const tick = async () => {
      if (stopped) return
      n += 1
      setTries(n)
      try {
        const { data } = await hostApi.get<EventOut>(`/events/${p.eventId}`)
        if (succeeded(data, p)) {
          clearPending()
          await qc.invalidateQueries({ queryKey: qk.events })
          qc.setQueryData(qk.event(p.eventId), data)
          if (!stopped) setPhase('ok')
          return
        }
      } catch { /* повторим */ }
      if (n >= MAX_TRIES) { if (!stopped) setPhase('timeout'); return }
      setTimeout(tick, EVERY_MS)
    }
    void tick()
    return () => { stopped = true }
    // nonce — ручной перезапуск проверки после таймаута
  }, [nonce, phase, qc])

  const goBack = () => navigate(pending.current?.returnTo ?? (eventId ? `/app/events/${eventId}` : '/app'), { replace: true })

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', justifyContent: 'center' }}>
      <div style={{ width: '100%', maxWidth: 440, padding: 'calc(72px + env(safe-area-inset-top)) 24px 32px', textAlign: 'center' }}>
        {phase === 'checking' && (
          <>
            <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 24 }}><Spinner style={{ width: 36, height: 36 }} /></div>
            <h1 className="host-title" style={{ marginBottom: 10 }}>Проверяем оплату</h1>
            <p className="host-muted" style={{ marginBottom: 28 }}>
              Банк подтверждает платёж, обычно это занимает несколько секунд. Попытка {tries} из {MAX_TRIES}.
            </p>
            <button className="btn-ghost" onClick={goBack}>Проверить позже</button>
          </>
        )}
        {phase === 'ok' && (
          <>
            <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 22 }}>
              <span className="host-badge" style={{ color: 'var(--success)', fontSize: 20, padding: '6px 16px', borderWidth: 3, transform: 'rotate(-4deg)' }}>Оплачено</span>
            </div>
            <h1 className="host-title" style={{ marginBottom: 10 }}>Оплата прошла</h1>
            <p className="host-muted" style={{ marginBottom: 28 }}>Изменения уже применены к альбому.</p>
            <button className="btn" onClick={goBack}>Перейти к событию</button>
          </>
        )}
        {phase === 'timeout' && (
          <>
            <h1 className="host-title" style={{ marginBottom: 10 }}>Платёж ещё обрабатывается</h1>
            <p className="host-muted" style={{ marginBottom: 28 }}>
              Подтверждение пока не пришло. Если деньги списались, изменения появятся в течение нескольких минут.
            </p>
            <button className="btn" onClick={() => { setTries(0); setPhase('checking'); setNonce((v) => v + 1) }} style={{ marginBottom: 10 }}>Проверить ещё раз</button>
            <button className="btn-ghost" onClick={goBack}>Вернуться к событию</button>
          </>
        )}
        {phase === 'unknown' && (
          <>
            <h1 className="host-title" style={{ marginBottom: 10 }}>Платёж не найден</h1>
            <p className="host-muted" style={{ marginBottom: 28 }}>
              Не удалось определить, за что была оплата. Откройте событие и проверьте его статус.
            </p>
            <button className="btn" onClick={() => navigate('/app', { replace: true })}>К моим альбомам</button>
          </>
        )}
      </div>
    </div>
  )
}
