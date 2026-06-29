import { useParams } from 'react-router-dom'

function getEventMeta() {
  try { return JSON.parse(sessionStorage.getItem('event') ?? '{}') } catch { return {} }
}

// Film reel icon from the design
function FilmReelIcon() {
  return (
    <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <path d="M6 2h12M6 22h12M8 2v6l4 4 4-4V2M8 22v-6l4-4 4 4v6"/>
    </svg>
  )
}

export default function EventEndedScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const event = getEventMeta()
  const eventTitle: string = event.title ?? 'Событие'

  return (
    <div style={{
      minHeight: '100dvh', background: 'var(--paper)',
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: '60px 24px 32px', textAlign: 'center', gap: 18,
    }}>
      {/* Film reel icon */}
      <div style={{
        width: 96, height: 96, borderRadius: '50%',
        background: 'var(--paper-2)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: 'var(--ink-3)', marginBottom: 8,
        border: '1px solid var(--line)',
      }}>
        <FilmReelIcon />
      </div>

      <h1 style={{
        fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500,
        fontSize: 32, letterSpacing: '-.02em', lineHeight: 1.05,
      }}>
        Мероприятие уже закончилось
      </h1>

      <p style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5, maxWidth: 280 }}>
        Плёнка проявилась. Все кадры доступны в альбоме мероприятия.
      </p>

      {eventTitle && (
        <div style={{ marginTop: 16, fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.14em', color: 'var(--ink-4)', textTransform: 'uppercase' }}>
          {eventTitle.toUpperCase()}
        </div>
      )}

      <a
        href={`/g/${shortCode}/album`}
        className="btn-ghost btn-sm"
        style={{ marginTop: 6, padding: '0 22px', width: 'auto', display: 'inline-flex', textDecoration: 'none' }}
      >
        Посмотреть альбом
      </a>
    </div>
  )
}
