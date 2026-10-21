import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Navigate, useNavigate, useSearchParams } from 'react-router-dom'
import { apiErrorMessage, deviceFingerprint, hostApi, hostTokens, type Schemas } from '../api/hostClient'
import { Spinner } from '../ui'

const DOC_VERSION = '2.4'
const DOC_TYPES = ['offer', 'privacy', 'consent', 'content_rules', 'age_confirmation'] as const

function safeNext(raw: string | null): string {
  if (raw && raw.startsWith('/app') && !raw.startsWith('/app/login')) return raw
  return '/app'
}

function AuthLayout({ children }: { children: React.ReactNode }) {
  return (
    <div className="host-auth">
      <div className="host-auth-inner">
        <div className="host-auth-strip" aria-hidden="true" />
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 36 }}>
          <img src="/brand/im-mark-F-light.svg" alt="" width={36} height={36}
            onError={(e) => { (e.currentTarget as HTMLImageElement).style.display = 'none' }} />
          <span style={{ fontFamily: 'Playfair Display, serif', fontWeight: 700, fontSize: 22, letterSpacing: '-.01em' }}>
            Impo<span style={{ color: 'var(--amber-2)' }}>Mento</span>
          </span>
        </div>
        {children}
      </div>
    </div>
  )
}

export function LoginScreen() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const [email, setEmail] = useState(params.get('email') ?? '')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (hostTokens.isLoggedIn()) return <Navigate to={safeNext(params.get('next'))} replace />

  const submit = async (e: FormEvent) => {
    e.preventDefault()
    const value = email.trim().toLowerCase()
    if (!/^\S+@\S+\.\S+$/.test(value)) {
      setError('Проверьте адрес почты')
      return
    }
    setLoading(true)
    setError(null)
    try {
      await hostApi.post('/auth/email/request', { email: value })
      const next = params.get('next')
      navigate(`/app/login/code?email=${encodeURIComponent(value)}${next ? `&next=${encodeURIComponent(next)}` : ''}`)
    } catch (err) {
      setError(apiErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <AuthLayout>
      <div className="host-kicker">Вход для организатора</div>
      <h1 className="host-title" style={{ margin: '8px 0 10px' }}>Создавайте альбомы событий</h1>
      <p className="host-muted" style={{ marginBottom: 28 }}>
        Пришлём код на почту. Регистрация и пароль не нужны.
      </p>
      <form onSubmit={submit} style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
        <label className="host-field-label" htmlFor="email">Электронная почта</label>
        <input
          id="email"
          className="input-field"
          type="email"
          inputMode="email"
          autoComplete="email"
          placeholder="you@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          autoFocus
        />
        {error && <div style={{ color: 'var(--shutter)', fontSize: 13 }}>{error}</div>}
        <button className="btn" type="submit" disabled={loading} style={{ marginTop: 8 }}>
          {loading ? <Spinner style={{ borderColor: 'rgba(255,255,255,.3)', borderTopColor: '#fff' }} /> : 'Получить код'}
        </button>
      </form>
      <p className="host-muted" style={{ fontSize: 12, marginTop: 20 }}>
        Продолжая, вы принимаете <a href="/offer.html" target="_blank" rel="noreferrer">оферту</a> и{' '}
        <a href="/privacy.html" target="_blank" rel="noreferrer">политику конфиденциальности</a>.
      </p>
      <div style={{ flex: 1 }} />
      <a href="/join?guest=1" className="host-muted" style={{ textAlign: 'center', fontSize: 14, marginTop: 32 }}>
        Я гость — ввести код альбома
      </a>
    </AuthLayout>
  )
}

const RESEND_SECONDS = 48

export function CodeScreen() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const email = params.get('email') ?? ''
  const [digits, setDigits] = useState<string[]>(Array(6).fill(''))
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [left, setLeft] = useState(RESEND_SECONDS)
  const inputs = useRef<Array<HTMLInputElement | null>>([])

  useEffect(() => {
    if (left <= 0) return
    const t = setTimeout(() => setLeft((v) => v - 1), 1000)
    return () => clearTimeout(t)
  }, [left])

  if (!email) return <Navigate to="/app/login" replace />

  const verify = async (code: string) => {
    setLoading(true)
    setError(null)
    try {
      let refCode: string | undefined
      try { refCode = localStorage.getItem('pending_ref_code') ?? undefined } catch { /* ignore */ }
      const { data } = await hostApi.post<Schemas['TokenOut']>('/auth/email/verify', {
        email, code, fingerprint: deviceFingerprint(), ref_code: refCode,
      })
      hostTokens.save(data)
      try { localStorage.removeItem('pending_ref_code') } catch { /* ignore */ }
      const next = safeNext(params.get('next'))
      try {
        const { data: status } = await hostApi.get<Schemas['ConsentStatusOut']>('/consent/status')
        if (status.needs_accept) {
          navigate(`/app/consent?next=${encodeURIComponent(next)}`, { replace: true })
          return
        }
      } catch { /* статус согласий не критичен для входа */ }
      navigate(next, { replace: true })
    } catch (err) {
      setError(apiErrorMessage(err, 'Неверный код'))
      setDigits(Array(6).fill(''))
      inputs.current[0]?.focus()
    } finally {
      setLoading(false)
    }
  }

  const setDigit = (index: number, raw: string) => {
    const clean = raw.replace(/\D/g, '')
    if (clean.length > 1) {
      // Вставка кода целиком
      const next = clean.slice(0, 6).split('')
      const filled = [...next, ...Array(6 - next.length).fill('')]
      setDigits(filled)
      if (next.length === 6) void verify(next.join(''))
      else inputs.current[next.length]?.focus()
      return
    }
    const next = [...digits]
    next[index] = clean
    setDigits(next)
    if (clean && index < 5) inputs.current[index + 1]?.focus()
    if (next.every((d) => d)) void verify(next.join(''))
  }

  const resend = async () => {
    setError(null)
    try {
      await hostApi.post('/auth/email/request', { email })
      setLeft(RESEND_SECONDS)
    } catch (err) {
      setError(apiErrorMessage(err))
    }
  }

  return (
    <AuthLayout>
      <div className="host-kicker">Код из письма</div>
      <h1 className="host-title" style={{ margin: '8px 0 10px' }}>Проверьте почту</h1>
      <p className="host-muted" style={{ marginBottom: 28 }}>
        Отправили 6 цифр на <b style={{ color: 'var(--ink)' }}>{email}</b>
      </p>
      <div style={{ display: 'flex', gap: 8, justifyContent: 'space-between' }}>
        {digits.map((d, i) => (
          <input
            key={i}
            ref={(el) => { inputs.current[i] = el }}
            value={d}
            onChange={(e) => setDigit(i, e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Backspace' && !digits[i] && i > 0) inputs.current[i - 1]?.focus()
            }}
            inputMode="numeric"
            autoComplete={i === 0 ? 'one-time-code' : 'off'}
            aria-label={`Цифра ${i + 1}`}
            autoFocus={i === 0}
            disabled={loading}
            style={{
              width: '100%', maxWidth: 52, height: 60, textAlign: 'center',
              fontFamily: 'Inter, sans-serif', fontSize: 24, fontWeight: 600,
              borderRadius: 14, border: d ? '1px solid var(--amber)' : '1px solid var(--line)',
              background: 'var(--paper-2)', color: 'var(--ink)', outline: 'none',
            }}
          />
        ))}
      </div>
      {loading && <div style={{ display: 'flex', justifyContent: 'center', marginTop: 20 }}><Spinner /></div>}
      {error && <div style={{ color: 'var(--shutter)', fontSize: 13, marginTop: 14 }}>{error}</div>}
      <div style={{ marginTop: 24, fontSize: 14 }}>
        {left > 0 ? (
          <span className="host-muted">Отправить код повторно через {left} с</span>
        ) : (
          <button onClick={resend} style={{ background: 'none', border: 'none', color: 'var(--amber)', fontWeight: 600, cursor: 'pointer', padding: 0, fontSize: 14 }}>
            Отправить код ещё раз
          </button>
        )}
      </div>
      <button
        onClick={() => navigate(`/app/login?email=${encodeURIComponent(email)}`)}
        style={{ marginTop: 14, alignSelf: 'flex-start', background: 'none', border: 'none', color: 'var(--ink-3)', cursor: 'pointer', padding: 0, fontSize: 14 }}
      >
        Изменить почту
      </button>
    </AuthLayout>
  )
}

export function ConsentScreen() {
  const navigate = useNavigate()
  const [params] = useSearchParams()
  const [agreed, setAgreed] = useState(false)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (!hostTokens.isLoggedIn()) return <Navigate to="/app/login" replace />

  const accept = async () => {
    setLoading(true)
    setError(null)
    try {
      for (const docType of DOC_TYPES) {
        await hostApi.post('/consent', { doc_type: docType, doc_version: DOC_VERSION })
      }
      navigate(safeNext(params.get('next')), { replace: true })
    } catch (err) {
      setError(apiErrorMessage(err))
    } finally {
      setLoading(false)
    }
  }

  return (
    <AuthLayout>
      <div className="host-kicker">Последний шаг</div>
      <h1 className="host-title" style={{ margin: '8px 0 20px' }}>Документы</h1>
      <label style={{ display: 'flex', gap: 12, alignItems: 'flex-start', cursor: 'pointer' }}>
        <input type="checkbox" checked={agreed} onChange={(e) => setAgreed(e.target.checked)}
          style={{ width: 22, height: 22, marginTop: 2, accentColor: 'var(--amber)', flexShrink: 0 }} />
        <span style={{ fontSize: 14, lineHeight: 1.5, color: 'var(--ink-2)' }}>
          Мне есть 14 лет. Я принимаю <a href="/offer.html" target="_blank" rel="noreferrer">оферту</a>,{' '}
          <a href="/content-rules.html" target="_blank" rel="noreferrer">правила контента</a> и даю{' '}
          <a href="/consent.html" target="_blank" rel="noreferrer">согласие на обработку данных</a> по{' '}
          <a href="/privacy.html" target="_blank" rel="noreferrer">политике</a>.
        </span>
      </label>
      {error && <div style={{ color: 'var(--shutter)', fontSize: 13, marginTop: 14 }}>{error}</div>}
      <button className="btn" style={{ marginTop: 28 }} disabled={!agreed || loading} onClick={accept}>
        {loading ? <Spinner style={{ borderColor: 'rgba(255,255,255,.3)', borderTopColor: '#fff' }} /> : 'Продолжить'}
      </button>
    </AuthLayout>
  )
}
