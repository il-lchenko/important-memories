// Экран использования invite-токена в PWA.
// GET /guest/invites/{token} → preview → confirm → POST /join → камера.
import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api } from '../../api/client'

interface InvitePreview {
  display_name: string
  event_title: string
  event_short_code: string
  event_status?: string
  public_share_token?: string | null
  used: boolean
  expired: boolean
  event_closed?: boolean
}

interface JoinResponse {
  guest_token: string
  guest_id: string
  name: string
  event: {
    id: string
    title: string
    settings: { lut_preset: string }
  }
  frames_remaining: number
}

function generateFingerprint(): string {
  const NEW_KEY = 'im_fp_v2'
  try {
    const existing = localStorage.getItem(NEW_KEY)
    if (existing && /^[a-f0-9]{16,64}$/.test(existing)) return existing
    const bytes = new Uint8Array(16)
    crypto.getRandomValues(bytes)
    const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
    localStorage.setItem(NEW_KEY, hex)
    return hex
  } catch {
    return 'aaaabbbbccccdddd'
  }
}

function saveSession(shortCode: string, token: string, guestId: string, guestName: string, event: unknown) {
  const ev = JSON.stringify(event)
  sessionStorage.setItem('guest_token', token)
  sessionStorage.setItem('guest_id', guestId)
  sessionStorage.setItem('guest_name', guestName)
  sessionStorage.setItem('event', ev)
  localStorage.setItem(`gt_${shortCode}`, token)
  localStorage.setItem(`gi_${shortCode}`, guestId)
  localStorage.setItem(`gn_${shortCode}`, guestName)
  localStorage.setItem(`ge_${shortCode}`, ev)
}

export default function InvitePage() {
  const { token } = useParams<{ token: string }>()
  const navigate = useNavigate()
  const [loading, setLoading] = useState(true)
  const [preview, setPreview] = useState<InvitePreview | null>(null)
  const [name, setName] = useState('')
  const [joining, setJoining] = useState(false)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    if (!token) return
    api.get<InvitePreview>(`/guest/invites/${token}`)
      .then(({ data }) => {
        setPreview(data)
        setName(data.display_name)
      })
      .catch((e: unknown) => {
        const err = e as { response?: { data?: { error?: { message?: string } } } }
        setError(err?.response?.data?.error?.message ?? 'Приглашение не найдено')
      })
      .finally(() => setLoading(false))
  }, [token])

  const handleJoin = async () => {
    if (!token || !name.trim()) return
    setJoining(true)
    setError(null)
    try {
      const { data } = await api.post<JoinResponse>(`/guest/invites/${token}/join`, {
        name: name.trim(),
        fingerprint: generateFingerprint(),
      })
      saveSession(
        data.event.title, // не используется shortCode; сохраним по event_id ниже
        data.guest_token, data.guest_id, name.trim(), data.event,
      )
      // Дополнительно кладём под shortCode из preview — для восстановления сессии
      // на /g/<code>/... экранах.
      if (preview) {
        localStorage.setItem(`gt_${preview.event_short_code}`, data.guest_token)
        localStorage.setItem(`gi_${preview.event_short_code}`, data.guest_id)
        localStorage.setItem(`gn_${preview.event_short_code}`, name.trim())
        localStorage.setItem(`ge_${preview.event_short_code}`, JSON.stringify(data.event))
        navigate(`/g/${preview.event_short_code}/camera`)
      }
    } catch (e: unknown) {
      const err = e as { response?: { status?: number; data?: { error?: { message?: string; code?: string } } } }
      const code = err?.response?.data?.error?.code
      if (code === 'CONFLICT') {
        setError('Приглашение уже использовано или истекло. Попросите новое.')
      } else {
        setError(err?.response?.data?.error?.message ?? 'Не удалось войти. Попробуйте ещё раз.')
      }
      setJoining(false)
    }
  }

  if (loading) {
    return (
      <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <div className="spinner" />
      </div>
    )
  }

  if (error && !preview) {
    return (
      <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: 24, textAlign: 'center' }}>
        <div style={{ fontSize: 48, marginBottom: 12 }}>🔗</div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontSize: 24, margin: '0 0 12px' }}>
          Ссылка не работает
        </h1>
        <p style={{ color: 'var(--ink-3)', fontSize: 14, lineHeight: 1.5, margin: 0 }}>{error}</p>
        <button className="btn" style={{ marginTop: 24 }} onClick={() => navigate('/')}>
          На главную
        </button>
      </div>
    )
  }

  if (!preview) return null

  if (preview.used) {
    return (
      <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: 24, textAlign: 'center' }}>
        <div style={{ fontSize: 48, marginBottom: 12 }}>🔒</div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontSize: 24, margin: '0 0 12px' }}>
          Приглашение использовано
        </h1>
        <p style={{ color: 'var(--ink-3)', fontSize: 14, lineHeight: 1.5, margin: 0 }}>
          Одноразовая ссылка уже сработала. Попросите хоста создать новое приглашение.
        </p>
        <button className="btn" style={{ marginTop: 24 }} onClick={() => navigate('/')}>
          На главную
        </button>
      </div>
    )
  }

  if (preview.expired) {
    return (
      <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: 24, textAlign: 'center' }}>
        <div style={{ fontSize: 48, marginBottom: 12 }}>⌛</div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontSize: 24, margin: '0 0 12px' }}>
          Ссылка истекла
        </h1>
        <p style={{ color: 'var(--ink-3)', fontSize: 14, lineHeight: 1.5, margin: 0 }}>
          Срок действия приглашения истёк.
        </p>
        <button className="btn" style={{ marginTop: 24 }} onClick={() => navigate('/')}>
          На главную
        </button>
      </div>
    )
  }

  if (preview.event_closed) {
    const publicToken = preview.public_share_token
    return (
      <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', justifyContent: 'center', padding: 24, textAlign: 'center' }}>
        <div style={{ fontSize: 48, marginBottom: 12 }}>🎞️</div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontSize: 24, margin: '0 0 12px' }}>
          Событие завершилось
        </h1>
        <p style={{ color: 'var(--ink-3)', fontSize: 14, lineHeight: 1.5, margin: 0 }}>
          «{preview.event_title}» уже закрыт для съёмки.
          {publicToken ? ' Откройте альбом по публичной ссылке ниже.' : ''}
        </p>
        {publicToken && (
          <button
            className="btn"
            style={{ marginTop: 24 }}
            onClick={() => navigate(`/a/${publicToken}`)}
          >
            Открыть альбом
          </button>
        )}
        <button
          className={publicToken ? 'btn-ghost' : 'btn'}
          style={{ marginTop: 12 }}
          onClick={() => navigate('/')}
        >
          На главную
        </button>
      </div>
    )
  }

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '20px 24px 0', display: 'flex' }}>
        <div style={{
          padding: '4px 10px', background: 'rgba(201,136,30,.15)',
          borderRadius: 6, fontSize: 10, letterSpacing: '.14em', fontWeight: 700,
          color: 'var(--amber)', fontFamily: 'Inter, sans-serif',
        }}>
          ЛИЧНОЕ ПРИГЛАШЕНИЕ
        </div>
      </div>
      <div style={{ padding: '18px 24px', flex: 1 }}>
        <h1 style={{
          fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500,
          fontSize: 32, lineHeight: 1.05, letterSpacing: '-.02em', margin: '0 0 12px',
        }}>
          Вас ждут на<br />«{preview.event_title}»
        </h1>
        <p style={{ color: 'var(--ink-3)', fontSize: 14, lineHeight: 1.5, margin: '0 0 20px' }}>
          Хост создал персональную ссылку для «{preview.display_name}». Никакого PIN — сразу к камере.
        </p>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 10, letterSpacing: '.14em', color: 'var(--ink-3)', textTransform: 'uppercase', marginBottom: 8 }}>
          Ваше имя
        </div>
        <input
          className="input-display"
          value={name}
          onChange={(e) => setName(e.target.value)}
          maxLength={40}
          placeholder="Так вас увидят в альбоме"
        />
        {error && <p style={{ color: 'var(--shutter)', fontSize: 13, marginTop: 8 }}>{error}</p>}
      </div>
      <div style={{ padding: '16px 20px', paddingBottom: 'max(env(safe-area-inset-bottom, 16px), 16px)' }}>
        <button
          className="btn"
          onClick={handleJoin}
          disabled={joining || !name.trim()}
        >
          {joining ? 'Входим...' : 'Войти в альбом'}
          {!joining && <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="13 6 19 12 13 18"/></svg>}
        </button>
      </div>
    </div>
  )
}
