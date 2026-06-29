import { useNavigate, useParams, useLocation } from 'react-router-dom'

interface SignState {
  photoUrl: string
  ratio: number
  frameNum: number
  guestName?: string
}

export default function SignChoiceScreen() {
  const { shortCode, frameId } = useParams<{ shortCode: string; frameId: string }>()
  const navigate = useNavigate()
  const { state } = useLocation() as { state: SignState | null }

  if (!state?.photoUrl) {
    navigate(`/g/${shortCode}/camera`, { replace: true })
    return null
  }

  const goCamera = () => navigate(`/g/${shortCode}/camera`)
  const goText = () => navigate(`/g/${shortCode}/sign/${frameId}/text`, { state })
  const goVoice = () => navigate(`/g/${shortCode}/sign/${frameId}/voice`, { state })

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
      <div style={{ paddingTop: 'max(env(safe-area-inset-top, 12px), 12px)', padding: '12px 14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <button onClick={goCamera} aria-label="Назад"
          style={{ width: 34, height: 34, borderRadius: '50%', background: 'rgba(0,0,0,0.06)', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--ink-2)' }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="11 18 5 12 11 6"/><line x1="5" y1="12" x2="19" y2="12"/>
          </svg>
        </button>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.14em', color: 'var(--ink-3)' }}>
          ПОДПИСЬ К КАДРУ {String(state.frameNum).padStart(2, '0')}
        </div>
        <div style={{ width: 34 }} />
      </div>

      <div style={{ padding: '12px 24px 0', textAlign: 'center' }}>
        <div style={{ display: 'inline-block', background: 'var(--paper)', padding: '12px 12px 0', borderRadius: 3, boxShadow: '0 8px 24px rgba(0,0,0,.25)', transform: 'rotate(-1.5deg)' }}>
          <div style={{ width: 130, aspectRatio: String(state.ratio), background: '#000', borderRadius: 2, overflow: 'hidden' }}>
            <img src={state.photoUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div>
          <div style={{ height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: 'Caveat, cursive', fontSize: 14, color: 'var(--ink-2)' }}>
            {state.guestName ?? 'Гость'}
          </div>
        </div>
      </div>

      <div style={{ padding: '22px 24px 0' }}>
        <h2 style={{ fontFamily: 'Fraunces, serif', fontWeight: 500, fontSize: 22, lineHeight: 1.15, marginBottom: 6, color: 'var(--ink)' }}>
          Как подписать кадр?
        </h2>
        <p style={{ fontSize: 12, color: 'var(--ink-3)', lineHeight: 1.4 }}>
          Выберите способ — текст или голосовое сообщение.
        </p>
      </div>

      <div style={{ padding: '18px 20px 0', display: 'flex', gap: 10 }}>
        <button onClick={goText} aria-label="Подписать текстом"
          style={{ flex: 1, background: 'var(--paper-2)', border: '1.5px solid var(--line)', borderRadius: 14, padding: '18px 12px', cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}
        >
          <div style={{ width: 44, height: 44, borderRadius: '50%', background: 'rgba(201,136,30,.12)', color: 'var(--amber)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
              <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
            </svg>
          </div>
          <div style={{ fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14, color: 'var(--ink)' }}>Текстом</div>
          <div style={{ fontSize: 11, color: 'var(--ink-3)', lineHeight: 1.3, textAlign: 'center' }}>
            Короткая фраза<br/>до 120 символов
          </div>
        </button>

        <button onClick={goVoice} aria-label="Подписать голосом"
          style={{ flex: 1, background: 'var(--paper-2)', border: '1.5px solid var(--line)', borderRadius: 14, padding: '18px 12px', cursor: 'pointer', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}
        >
          <div style={{ width: 44, height: 44, borderRadius: '50%', background: 'rgba(201,136,30,.12)', color: 'var(--amber)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 1a3 3 0 0 0-3 3v8a3 3 0 0 0 6 0V4a3 3 0 0 0-3-3z"/>
              <path d="M19 10v2a7 7 0 0 1-14 0v-2"/>
              <line x1="12" y1="19" x2="12" y2="23"/>
              <line x1="8" y1="23" x2="16" y2="23"/>
            </svg>
          </div>
          <div style={{ fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14, color: 'var(--ink)' }}>Голосом</div>
          <div style={{ fontSize: 11, color: 'var(--ink-3)', lineHeight: 1.3, textAlign: 'center' }}>
            Запись<br/>до 20 секунд
          </div>
        </button>
      </div>

      <div style={{ flex: 1 }} />

      <div style={{ padding: '12px 16px max(env(safe-area-inset-bottom, 16px), 16px)' }}>
        <button onClick={goCamera}
          style={{ width: '100%', padding: '14px 16px', borderRadius: 12, background: 'transparent', color: 'var(--ink-3)', border: '1px solid var(--line)', cursor: 'pointer', fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14 }}
        >
          Пропустить
        </button>
      </div>
    </div>
  )
}
