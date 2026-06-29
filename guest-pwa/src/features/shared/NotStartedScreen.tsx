import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { guestApi } from '../../api/client'

function getStartAt(): Date | null {
  try {
    const raw = sessionStorage.getItem('event')
    if (!raw) return null
    const startAt = JSON.parse(raw).start_at
    return startAt ? new Date(startAt) : null
  } catch { return null }
}

function pad(n: number): string { return String(n).padStart(2, '0') }

const SOON_THRESHOLD_MS = 15 * 60 * 1000

export default function NotStartedScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const startAt = getStartAt()
  const navigatedRef = useRef(false)

  const [remaining, setRemaining] = useState(() =>
    startAt ? Math.max(0, startAt.getTime() - Date.now()) : 0
  )

  const goToCamera = () => {
    if (navigatedRef.current) return
    navigatedRef.current = true
    navigate(`/g/${shortCode}/camera`, { replace: true })
  }

  useEffect(() => {
    const calc = () => startAt ? Math.max(0, startAt.getTime() - Date.now()) : 0

    const tick = setInterval(() => {
      const ms = calc()
      setRemaining(ms)
      if (ms === 0) goToCamera()
    }, 1000)

    const onVisibility = () => {
      if (!document.hidden) {
        const ms = calc()
        setRemaining(ms)
        if (ms === 0) goToCamera()
      }
    }
    document.addEventListener('visibilitychange', onVisibility)

    return () => {
      clearInterval(tick)
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [startAt]) // eslint-disable-line react-hooks/exhaustive-deps

  // Poll backend every 30s — host might have manually activated the event early
  useEffect(() => {
    const poll = setInterval(async () => {
      try {
        const { data } = await guestApi.getSession()
        if (data.event.status === 'active') {
          const nowStartAt = data.event.start_at
          if (!nowStartAt || new Date(nowStartAt) <= new Date()) {
            goToCamera()
          }
        }
      } catch {}
    }, 30_000)
    return () => clearInterval(poll)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const totalSec = Math.floor(remaining / 1000)
  const hours = Math.floor(totalSec / 3600)
  const mins = Math.floor((totalSec % 3600) / 60)
  const secs = totalSec % 60
  const isSoon = remaining > 0 && remaining <= SOON_THRESHOLD_MS

  const startLabel = startAt
    ? startAt.toLocaleString('ru', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })
    : null

  return (
    <div className="darkroom" style={{ minHeight: '100dvh', position: 'relative' }}>
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', background: 'radial-gradient(circle at 30% 25%, rgba(255,179,71,.15) 0%, transparent 50%), radial-gradient(circle at 70% 80%, rgba(213,75,61,.12) 0%, transparent 55%)' }} />

      <div style={{ padding: '60px 24px 24px', position: 'relative', height: '100%', display: 'flex', flexDirection: 'column', minHeight: '100dvh' }}>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.18em', color: 'var(--dr-amber)', textTransform: 'uppercase' }}>
          {isSoon ? 'Почти начинаем' : 'Скоро мероприятие'}
        </div>

        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 32, lineHeight: 1.05, letterSpacing: '-.02em', margin: '6px 0 32px', maxWidth: 300 }}>
          {isSoon
            ? 'Совсем скоро начнём!'
            : 'Мероприятие ещё не началось.'}
        </h1>

        {/* Countdown grid */}
        {startAt && (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
            {[
              { num: pad(hours), label: 'часов' },
              { num: pad(mins), label: 'минут' },
              { num: pad(secs), label: 'секунд' },
            ].map(({ num, label }) => (
              <div key={label} style={{
                aspectRatio: '1/1', borderRadius: 20,
                background: isSoon ? 'rgba(255,179,71,.1)' : 'rgba(255,179,71,.06)',
                border: `1px solid rgba(255,179,71,${isSoon ? '.3' : '.18'})`,
                display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8,
                transition: 'background .4s, border-color .4s',
              }}>
                <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 56, fontWeight: 500, color: 'var(--dr-text)', lineHeight: 1, letterSpacing: '-.02em' }}>
                  {num}
                </div>
                <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.2em', color: 'var(--dr-amber)', textTransform: 'uppercase' }}>
                  {label}
                </div>
              </div>
            ))}
          </div>
        )}

        {startLabel && (
          <div style={{ marginTop: 14, fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.14em', color: 'rgba(240,230,210,.5)', textTransform: 'uppercase' }}>
            Начнётся {startLabel}
          </div>
        )}

        {/* Quote */}
        <div style={{
          marginTop: 'auto', marginBottom: 24,
          padding: 20, borderRadius: 16,
          background: 'rgba(255,179,71,.06)',
          borderLeft: '2px solid var(--dr-amber)',
          fontFamily: 'Fraunces, serif', fontStyle: 'italic',
          fontSize: 17, lineHeight: 1.4, color: 'var(--dr-text)',
        }}>
          <span style={{ fontSize: 36, lineHeight: 0, color: 'var(--dr-amber)', marginRight: 4, verticalAlign: -16 }}>"</span>
          Лучшие кадры рождаются в неожиданный момент. Будьте готовы.
        </div>
      </div>
    </div>
  )
}
