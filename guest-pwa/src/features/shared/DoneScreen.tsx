import { useNavigate, useParams } from 'react-router-dom'

function getEventMeta() {
  try { return JSON.parse(sessionStorage.getItem('event') ?? '{}') } catch { return {} }
}

export default function DoneScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const event = getEventMeta()
  const guestName: string = sessionStorage.getItem('guest_name') ?? 'Гость'
  const eventTitle: string = event.title ?? ''
  const framesTotal: number = event.settings?.frames_per_guest ?? 24

  const revealAt: string | null = event.settings?.reveal_at ?? null
  const revealLabel = revealAt
    ? new Date(revealAt).toLocaleTimeString('ru', { hour: '2-digit', minute: '2-digit' })
    : null

  return (
    <div className="darkroom" style={{ display: 'flex', flexDirection: 'column', minHeight: '100dvh' }}>
      {/* Top meta bar */}
      <div style={{
        padding: '0 24px', paddingTop: 60,
        fontFamily: 'JetBrains Mono, monospace', fontSize: 11,
        letterSpacing: '.14em', color: 'rgba(240,230,210,.45)',
        textTransform: 'uppercase',
        display: 'flex', justifyContent: 'space-between',
      }}>
        <span>{guestName.toUpperCase()}</span>
        <span>{eventTitle.toUpperCase()}</span>
      </div>

      {/* Core */}
      <div style={{ flex: 1, padding: '32px 24px', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 24 }}>
        <div style={{
          fontFamily: 'JetBrains Mono, monospace',
          fontSize: 180, fontWeight: 500,
          color: 'var(--dr-amber)', lineHeight: 1, letterSpacing: '-.06em',
          textShadow: '0 0 60px rgba(255,179,71,.3)',
        }}>
          {framesTotal}
        </div>
        <h1 style={{
          fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500,
          fontSize: 32, lineHeight: 1.05, letterSpacing: '-.02em',
          margin: 0, textAlign: 'center', color: 'var(--dr-text)',
        }}>
          Ваша плёнка<br />окончена.
        </h1>
        <p style={{ fontSize: 14, color: 'rgba(240,230,210,.55)', textAlign: 'center', lineHeight: 1.5, maxWidth: 280 }}>
          Кадры увидите в общем альбоме после проявки.
          {revealLabel && ` До неё — в ${revealLabel}.`}
        </p>
      </div>

      {/* Footer buttons */}
      <div style={{ padding: '14px 20px 30px', display: 'flex', flexDirection: 'column', gap: 10 }}>
        <button
          className="btn-dark-amber"
          onClick={() => navigate(`/g/${shortCode}/waiting`)}
        >
          Ждать проявки
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--dark)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M6 8a6 6 0 0 1 12 0v5l2 2H4l2-2V8z"/><path d="M10 19a2 2 0 0 0 4 0"/>
          </svg>
        </button>
        <button
          className="btn-ghost-dark btn-sm"
          onClick={() => navigate(`/g/${shortCode}/album`)}
        >
          К альбому{revealLabel ? ` · доступен ${revealLabel}` : ''}
        </button>
      </div>
    </div>
  )
}
