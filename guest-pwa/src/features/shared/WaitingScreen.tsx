import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { guestApi } from '../../api/client'

function getEventMeta() {
  try { return JSON.parse(sessionStorage.getItem('event') ?? '{}') } catch { return {} }
}

function getRevealAt(): Date | null {
  try {
    const raw = sessionStorage.getItem('event')
    if (!raw) return null
    const revealAt = JSON.parse(raw).settings?.reveal_at
    return revealAt ? new Date(revealAt) : null
  } catch { return null }
}

function pad(n: number): string { return String(n).padStart(2, '0') }

export default function WaitingScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const event = getEventMeta()
  const eventTitle: string = event.title ?? 'Ивент'
  const framesPerGuest: number = event.settings?.frames_per_guest ?? 0

  // revealAt starts from sessionStorage but is refreshed from server on mount
  const [revealAt, setRevealAt] = useState<Date | null>(() => getRevealAt())
  const [remaining, setRemaining] = useState(() => {
    const r = getRevealAt()
    return r ? Math.max(0, r.getTime() - Date.now()) : 0
  })
  const [framesLeft, setFramesLeft] = useState<number | null>(null)
  const navigatedRef = useRef(false)

  const openLabel = revealAt
    ? revealAt.toLocaleString('ru', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })
    : null

  const goToAlbum = () => {
    if (navigatedRef.current) return
    navigatedRef.current = true
    navigate(`/g/${shortCode}/album`, { replace: true })
  }

  // On mount: fetch fresh session data — updates reveal_at, frames, and checks if already revealed
  useEffect(() => {
    guestApi.getSession().then(({ data }) => {
      setFramesLeft(data.frames_remaining)
      if (data.event.status === 'completed') { goToAlbum(); return }

      const freshRevealAt = data.event.settings.reveal_at
      if (freshRevealAt) {
        const d = new Date(freshRevealAt)
        setRevealAt(d)
        const ms = Math.max(0, d.getTime() - Date.now())
        setRemaining(ms)
        if (ms === 0) { goToAlbum(); return }
        // Update sessionStorage so AlbumScreen and other screens have fresh data
        try {
          const raw = sessionStorage.getItem('event')
          if (raw) {
            const ev = JSON.parse(raw)
            if (ev.settings) ev.settings.reveal_at = freshRevealAt
            sessionStorage.setItem('event', JSON.stringify(ev))
          }
        } catch {}
      } else if (freshRevealAt === null) {
        // Host cleared the reveal_at — no timer
        setRevealAt(null)
        setRemaining(0)
      }
    }).catch(() => {})
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  // Countdown tick — also recalculates on tab focus to handle mobile background freezing
  useEffect(() => {
    const calc = () => revealAt ? Math.max(0, revealAt.getTime() - Date.now()) : 0

    const tick = setInterval(() => {
      const ms = calc()
      setRemaining(ms)
      if (revealAt && ms === 0) goToAlbum()
    }, 1000)

    const onVisibility = () => {
      if (!document.hidden) {
        const ms = calc()
        setRemaining(ms)
        if (revealAt && ms === 0) goToAlbum()
      }
    }
    document.addEventListener('visibilitychange', onVisibility)

    return () => {
      clearInterval(tick)
      document.removeEventListener('visibilitychange', onVisibility)
    }
  }, [revealAt]) // eslint-disable-line react-hooks/exhaustive-deps

  // Poll backend every 30s for manual host reveal or reveal_at update
  useEffect(() => {
    const poll = setInterval(async () => {
      try {
        const { data } = await guestApi.getSession()
        if (data.event.status === 'completed') { goToAlbum(); return }
        const freshRevealAt = data.event.settings.reveal_at
        if (freshRevealAt) {
          const d = new Date(freshRevealAt)
          setRevealAt(d)
          const ms = Math.max(0, d.getTime() - Date.now())
          setRemaining(ms)
          if (ms === 0) goToAlbum()
        }
      } catch {}
    }, 30_000)
    return () => clearInterval(poll)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  const totalSec = Math.floor(remaining / 1000)
  const hours = Math.floor(totalSec / 3600)
  const mins = Math.floor((totalSec % 3600) / 60)
  const secs = totalSec % 60
  // revealed only when there WAS a timer and it reached zero (not when revealAt is null)
  const revealed = revealAt !== null && remaining === 0

  return (
    <div className="darkroom" style={{ minHeight: '100dvh', position: 'relative' }}>
      {/* Ambient gradients */}
      <div style={{ position: 'absolute', inset: 0, pointerEvents: 'none', background: 'radial-gradient(circle at 30% 25%, rgba(255,179,71,.15) 0%, transparent 50%), radial-gradient(circle at 70% 80%, rgba(213,75,61,.12) 0%, transparent 55%)' }} />

      <div style={{ padding: '60px 24px 24px', position: 'relative', height: '100%', display: 'flex', flexDirection: 'column', minHeight: '100dvh' }}>
        {revealed ? (
          // ── Revealed state ──
          <>
            <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.18em', color: 'var(--dr-amber)', textTransform: 'uppercase' }}>
              Альбом открыт
            </div>
            <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 32, lineHeight: 1.05, letterSpacing: '-.02em', margin: '6px 0 40px', maxWidth: 280 }}>
              Плёнка проявилась!
            </h1>
            <div style={{ flex: 1 }} />
            <button className="btn-dark-amber" onClick={goToAlbum} style={{ width: '100%' }}>
              Открыть альбом
            </button>
          </>
        ) : (
          // ── Waiting state ──
          <>
            <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.18em', color: 'var(--dr-amber)', textTransform: 'uppercase' }}>
              {revealAt ? 'Скоро открытие' : 'Альбом ещё закрыт'}
            </div>
            <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 32, lineHeight: 1.05, letterSpacing: '-.02em', margin: '6px 0 32px', maxWidth: 280 }}>
              {revealAt ? <>Подождите —<br />осталось немного.</> : <>Альбом откроет<br />организатор.</>}
            </h1>

            {/* Clock grid */}
            {revealAt && (
              <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
                {[
                  { num: pad(hours), label: 'часов' },
                  { num: pad(mins), label: 'минут' },
                  { num: pad(secs), label: 'секунд' },
                ].map(({ num, label }) => (
                  <div key={label} style={{
                    aspectRatio: '1/1', borderRadius: 20,
                    background: 'rgba(255,179,71,.06)',
                    border: '1px solid rgba(255,179,71,.18)',
                    display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 8,
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

            {openLabel && (
              <div style={{ marginTop: 14, fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.14em', color: 'rgba(240,230,210,.5)', textTransform: 'uppercase' }}>
                Откроется {openLabel}
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
              Классные плёнки смотрят на следующее утро. Вашу — уже скоро.
            </div>

            {/* Back to camera unless we confirmed frames exhausted OR album is already revealed */}
            {(framesLeft === null || framesLeft > 0) && !revealed && (
              <button
                className="btn-dark-amber"
                onClick={() => navigate(`/g/${shortCode}/camera`)}
                style={{ width: '100%', marginBottom: 10 }}
              >
                Вернуться к камере
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--dark)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M3 7h4l2-3h6l2 3h4v13H3z"/><circle cx="12" cy="13" r="4"/>
                </svg>
              </button>
            )}

            {/* Meta */}
            <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.14em', color: 'rgba(240,230,210,.45)', textTransform: 'uppercase', display: 'flex', justifyContent: 'space-between', paddingBottom: 14 }}>
              {framesPerGuest > 0 && <span>ВАШИХ · {framesPerGuest}</span>}
              <span>{eventTitle.toUpperCase()}</span>
            </div>
          </>
        )}
      </div>
    </div>
  )
}
