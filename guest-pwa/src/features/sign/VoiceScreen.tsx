import { useEffect } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'

interface SignState {
  photoUrl: string
  ratio: number
  frameNum: number
  guestName?: string
}

// TODO: заменить на реальную ссылку в RuStore когда приложение опубликуется
const APP_INSTALL_URL = 'https://apps.rustore.ru/'

export default function VoiceScreen() {
  const { shortCode, frameId } = useParams<{ shortCode: string; frameId: string }>()
  const navigate = useNavigate()
  const { state } = useLocation() as { state: SignState | null }

  useEffect(() => {
    if (!state?.photoUrl) {
      navigate(`/g/${shortCode}/camera`, { replace: true })
    }
  }, [state, navigate, shortCode])

  if (!state?.photoUrl) return null

  const goBack = () => navigate(`/g/${shortCode}/sign/${frameId}`, { state })

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
      <div style={{ paddingTop: 'max(env(safe-area-inset-top, 12px), 12px)', padding: '12px 14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <button onClick={goBack} aria-label="Назад"
          style={{ width: 34, height: 34, borderRadius: '50%', background: 'rgba(0,0,0,0.06)', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--ink-2)', outline: 'none', WebkitTapHighlightColor: 'transparent' }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="11 18 5 12 11 6"/><line x1="5" y1="12" x2="19" y2="12"/>
          </svg>
        </button>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.14em', color: 'var(--ink-3)' }}>
          ГОЛОС К КАДРУ {String(state.frameNum).padStart(2, '0')}
        </div>
        <div style={{ width: 34 }} />
      </div>

      {/* Polaroid */}
      <div style={{ padding: '8px 24px 0', textAlign: 'center' }}>
        <div style={{ display: 'inline-block', background: 'var(--paper)', padding: '12px 12px 0', borderRadius: 3, boxShadow: '0 8px 24px rgba(0,0,0,.25)', transform: 'rotate(-1.5deg)' }}>
          <div style={{ width: 130, aspectRatio: String(state.ratio), background: '#000', borderRadius: 2, overflow: 'hidden' }}>
            <img src={state.photoUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div>
          <div style={{ height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: 'Caveat, cursive', fontSize: 14, color: 'var(--ink-2)' }}>
            {state.guestName ?? 'Гость'}
          </div>
        </div>
      </div>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16, padding: '24px' }}>
        <div style={{ width: 72, height: 72, borderRadius: '50%', background: 'rgba(201,136,30,.12)', color: 'var(--amber)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
            <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
            <line x1="12" y1="19" x2="12" y2="23"/>
            <line x1="8" y1="23" x2="16" y2="23"/>
          </svg>
        </div>

        <h2 style={{ fontFamily: 'Fraunces, serif', fontWeight: 500, fontSize: 22, lineHeight: 1.2, color: 'var(--ink-2)', textAlign: 'center', margin: 0 }}>
          Аудио‑подписи в приложении
        </h2>

        <p style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5, textAlign: 'center', maxWidth: 320, margin: 0 }}>
          Чтобы оставить голосовой комментарий к кадру, установите приложение Important Memories — там запись работает в один тап.
        </p>

        <a
          href={APP_INSTALL_URL}
          target="_blank"
          rel="noopener noreferrer"
          style={{
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
            width: '100%', maxWidth: 320, padding: '14px 22px',
            borderRadius: 12, background: 'var(--amber)', color: '#fff',
            border: 'none', textDecoration: 'none',
            fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14,
            cursor: 'pointer', outline: 'none', WebkitTapHighlightColor: 'transparent',
            touchAction: 'manipulation', marginTop: 4,
          }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ pointerEvents: 'none' }}>
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
            <polyline points="7 10 12 15 17 10"/>
            <line x1="12" y1="15" x2="12" y2="3"/>
          </svg>
          Установить приложение
        </a>

        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.12em', color: 'var(--ink-4)', textAlign: 'center', opacity: 0.7 }}>
          СКОРО В RUSTORE
        </div>
      </div>

      <div style={{ padding: '12px 16px max(env(safe-area-inset-bottom, 16px), 16px)', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <button onClick={goBack} type="button"
          style={{ width: '100%', padding: '14px 16px', borderRadius: 12, background: 'transparent', color: 'var(--ink-3)', border: '1px solid var(--line)', cursor: 'pointer', fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14, outline: 'none', WebkitTapHighlightColor: 'transparent', touchAction: 'manipulation' }}
        >
          Назад
        </button>
      </div>
    </div>
  )
}
