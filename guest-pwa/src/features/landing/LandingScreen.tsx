import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, guestApi } from '../../api/client'

interface EventPreview {
  title: string
  frames_per_guest: number
  reveal_at: string | null
  lut_preset: string
  status: string
}

function filmLabel(lut: string): string {
  const map: Record<string, string> = {
    portra400: 'Portra', portra: 'Portra', fuji400h: 'Fuji',
    cinestill: 'Cine', ilford: 'Ilford', original: 'Original',
  }
  return map[lut?.toLowerCase()] ?? lut?.split('_')[0] ?? '—'
}

function revealLabel(revealAt: string | null): string {
  if (!revealAt) return '—'
  try { return new Date(revealAt).toLocaleTimeString('ru', { hour: '2-digit', minute: '2-digit' }) }
  catch { return '—' }
}

// ── Film hero gradient (shared across screens) ──────────────────────────────
function FilmHero({ children }: { children?: React.ReactNode }) {
  return (
    <div style={{ position: 'relative', overflow: 'hidden', height: '100%', width: '100%' }}>
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(ellipse at 50% 40%, #f3cda0 0%, #c97e4a 50%, #6a3520 90%, #1f1208 100%)' }} />
      <div style={{ position: 'absolute', left: '38%', top: '30%', width: '24%', height: '55%', background: 'radial-gradient(ellipse at center, rgba(245,225,195,.7) 0%, transparent 70%)' }} />
      <div className="film-leak-tl" />
      <div className="film-leak-br" />
      <div className="film-vignette" />
      <svg className="film-grain" preserveAspectRatio="none" style={{ position: 'absolute', inset: 0 }}>
        <rect width="100%" height="100%" filter="url(#grain)" />
      </svg>
      {children}
    </div>
  )
}

// ── Step 1: Landing ──────────────────────────────────────────────────────────
function LandingStep({ preview, onNext }: { preview: EventPreview | null; onNext: () => void }) {
  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', position: 'relative' }}>
      {/* Hero */}
      <div style={{ height: 320, margin: '12px 16px 0', borderRadius: 24, overflow: 'hidden', position: 'relative', flexShrink: 0 }}>
        <FilmHero>
          {preview?.status === 'active' && (
            <div style={{
              position: 'absolute', left: 16, top: 14,
              height: 26, padding: '0 10px',
              background: 'rgba(0,0,0,.4)', backdropFilter: 'blur(8px)',
              color: 'var(--paper)', borderRadius: 999,
              fontSize: 11, fontWeight: 600, fontFamily: 'JetBrains Mono, monospace',
              letterSpacing: '.12em', display: 'inline-flex', alignItems: 'center', gap: 6,
            }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--shutter)', display: 'inline-block' }} />
              ИДЁТ
            </div>
          )}
        </FilmHero>
      </div>

      {/* Copy */}
      <div style={{ padding: '18px 24px 0' }}>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase' }}>
          Вас пригласили
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 38, lineHeight: 1, letterSpacing: '-.02em', margin: '8px 0 6px' }}>
          {preview?.title ?? '...'}
        </h1>
        {preview?.reveal_at && (
          <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 12, letterSpacing: '.08em', color: 'var(--ink-3)', marginBottom: 18 }}>
            ПРОЯВКА В {revealLabel(preview.reveal_at)}
          </div>
        )}

        {/* Meta grid */}
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
          borderRadius: 16, background: 'var(--paper-2)', padding: '14px 0', marginTop: preview?.reveal_at ? 0 : 18,
        }}>
          {[
            { v: preview ? String(preview.frames_per_guest) : '—', l: 'Кадра' },
            { v: revealLabel(preview?.reveal_at ?? null), l: 'Проявка' },
            { v: preview ? filmLabel(preview.lut_preset) : '—', l: 'Плёнка' },
          ].map((item, i) => (
            <div key={i} style={{ textAlign: 'center', position: 'relative' }}>
              {i > 0 && <div style={{ position: 'absolute', left: 0, top: 8, bottom: 8, width: 1, background: 'var(--line)' }} />}
              <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 20, fontWeight: 500, color: 'var(--ink)', lineHeight: 1 }}>{item.v}</div>
              <div style={{ fontSize: 10, letterSpacing: '.12em', color: 'var(--ink-3)', textTransform: 'uppercase', marginTop: 5, fontFamily: 'JetBrains Mono, monospace' }}>{item.l}</div>
            </div>
          ))}
        </div>
      </div>

      {/* CTA */}
      <div className="footer-gradient">
        {preview?.status === 'draft' ? (
          <div style={{ textAlign: 'center', padding: '0 24px' }}>
            <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.14em', color: 'var(--amber)', textTransform: 'uppercase', marginBottom: 8 }}>
              СКОРО
            </div>
            <div style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5 }}>
              Ивент ещё не начался. Хост откроет плёнку немного позже.
            </div>
          </div>
        ) : (
          <button className="btn" onClick={onNext}>
            Войти в плёнку
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <line x1="5" y1="12" x2="19" y2="12" /><polyline points="13 6 19 12 13 18" />
            </svg>
          </button>
        )}
      </div>
    </div>
  )
}

// ── Step 2: Name entry ───────────────────────────────────────────────────────
function NameStep({
  eventTitle, name, onChange, onBack, onNext, loading, error,
}: {
  eventTitle: string; name: string; onChange: (v: string) => void;
  onBack: () => void; onNext: () => void; loading: boolean; error: string | null;
}) {
  const inputRef = useRef<HTMLInputElement>(null)
  useEffect(() => { inputRef.current?.focus() }, [])

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', position: 'relative' }}>
      {/* Back link */}
      <button onClick={onBack} style={{ padding: '12px 24px 0', display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--ink-3)', fontFamily: 'JetBrains Mono, monospace', letterSpacing: '.04em', background: 'none', border: 'none', cursor: 'pointer', alignSelf: 'flex-start' }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 6 9 12 15 18"/></svg>
        {eventTitle || 'Назад'}
      </button>

      <div style={{ padding: '24px 24px 0' }}>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase' }}>
          Шаг 1 из 2
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 36, lineHeight: 1.05, letterSpacing: '-.02em', margin: '8px 0 6px' }}>
          Как вас<br />подписать?
        </h1>
        <p style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5, margin: '0 0 24px' }}>
          Имя появится под каждым вашим кадром в общем альбоме. Можно псевдоним.
        </p>

        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.14em', color: 'var(--ink-3)', textTransform: 'uppercase', marginBottom: 8 }}>
          Имя
        </div>
        <input
          ref={inputRef}
          className="input-display"
          placeholder="Например, Аня"
          value={name}
          onChange={(e) => onChange(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && !loading && name.trim() && onNext()}
          maxLength={40}
        />
        {error && <p style={{ color: 'var(--shutter)', fontSize: 13, marginTop: 8 }}>{error}</p>}

        <p style={{ fontSize: 11, color: 'var(--ink-4)', marginTop: 14, lineHeight: 1.5 }}>
          Гостю не нужен аккаунт. Имя видят только хост и&nbsp;участники этой плёнки.
        </p>
      </div>

      <div className="footer-gradient">
        <button className="btn" onClick={onNext} disabled={loading || !name.trim()}>
          {loading ? 'Входим...' : 'Дальше'}
          {!loading && <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="13 6 19 12 13 18"/></svg>}
        </button>
      </div>
    </div>
  )
}

// ── Step 3: Camera permission ────────────────────────────────────────────────
function PermissionStep({ eventTitle, guestName, onBack, onAllow }: {
  eventTitle: string; guestName: string; onBack: () => void; onAllow: () => void;
}) {
  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', position: 'relative' }}>
      {/* Back link */}
      <button onClick={onBack} style={{ padding: '12px 24px 0', display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--ink-3)', fontFamily: 'JetBrains Mono, monospace', letterSpacing: '.04em', background: 'none', border: 'none', cursor: 'pointer', alignSelf: 'flex-start' }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 6 9 12 15 18"/></svg>
        {guestName} · {eventTitle || 'Назад'}
      </button>

      <div style={{ padding: '24px 24px 0' }}>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase' }}>
          Шаг 2 из 2
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 32, lineHeight: 1.05, letterSpacing: '-.02em', margin: '8px 0 18px' }}>
          Откройте<br />доступ к&nbsp;камере
        </h1>

        {/* Permission card */}
        <div style={{ borderRadius: 20, background: 'var(--paper-2)', padding: 22, marginTop: 12 }}>
          <div style={{ width: 56, height: 56, borderRadius: 16, background: 'rgba(201,136,30,.12)', color: 'var(--amber)', display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 16 }}>
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 7h4l2-3h6l2 3h4v13H3z"/><circle cx="12" cy="13" r="4"/>
            </svg>
          </div>
          <h3 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 22, margin: '0 0 10px', letterSpacing: '-.01em' }}>
            Только на этот ивент
          </h3>
          <p style={{ margin: '0 0 14px', fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5 }}>
            Браузер спросит разрешение. Доступ выключается, как только вы закроете эту вкладку.
          </p>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10, paddingTop: 4, borderTop: '1px solid var(--line)', marginTop: 4 }}>
            {[
              'Фото остаются только в общей плёнке',
              'Никаких записей экрана и аналитики',
              'Никаких аккаунтов и email',
            ].map((text) => (
              <div key={text} style={{ display: 'flex', gap: 10, alignItems: 'flex-start', fontSize: 13, color: 'var(--ink-2)' }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="var(--success)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0, marginTop: 2 }}>
                  <polyline points="5 12 10 17 19 7"/>
                </svg>
                {text}
              </div>
            ))}
          </div>
        </div>
      </div>

      <div className="footer-gradient">
        <button className="btn" onClick={onAllow}>
          Разрешить
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="5 12 10 17 19 7"/></svg>
        </button>
      </div>
    </div>
  )
}

// ── Main component ───────────────────────────────────────────────────────────
export default function LandingScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const [step, setStep] = useState<'landing' | 'name' | 'permission'>('landing')
  const [name, setName] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [preview, setPreview] = useState<EventPreview | null>(null)

  useEffect(() => {
    if (!shortCode) return
    api.get<EventPreview>(`/guest/events/${shortCode}`)
      .then(({ data }) => setPreview(data))
      .catch(() => {})
  }, [shortCode])

  const handleJoin = async () => {
    if (!name.trim() || !shortCode) return
    setLoading(true)
    setError(null)
    try {
      const { data } = await guestApi.createSession(shortCode, name.trim())
      sessionStorage.setItem('guest_token', data.guest_token)
      sessionStorage.setItem('guest_id', data.guest_id)
      sessionStorage.setItem('guest_name', name.trim())
      sessionStorage.setItem('event', JSON.stringify(data.event))
      setStep('permission')
    } catch (err: unknown) {
      const d = (err as { response?: { data?: { error?: { message?: string }; detail?: string } } })?.response?.data
      const msg = d?.error?.message ?? d?.detail ?? 'Не удалось войти. Попробуйте ещё раз.'
      setError(msg)
    } finally {
      setLoading(false)
    }
  }

  if (step === 'landing') return <LandingStep preview={preview} onNext={() => setStep('name')} />
  if (step === 'name') return (
    <NameStep
      eventTitle={preview?.title ?? ''}
      name={name} onChange={setName}
      onBack={() => setStep('landing')}
      onNext={handleJoin}
      loading={loading} error={error}
    />
  )
  return (
    <PermissionStep
      eventTitle={preview?.title ?? ''}
      guestName={name}
      onBack={() => setStep('name')}
      onAllow={() => navigate(`/g/${shortCode}/camera`)}
    />
  )
}
