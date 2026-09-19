import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, guestApi } from '../../api/client'

interface EventPreview {
  title: string
  frames_per_guest: number
  reveal_at: string | null
  start_at?: string | null
  lut_preset: string
  status: string
  cover_url?: string | null
  pin_required?: boolean
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
function FilmHero({ children, coverUrl }: { children?: React.ReactNode; coverUrl?: string | null }) {
  return (
    <div style={{ position: 'relative', overflow: 'hidden', height: '100%', width: '100%' }}>
      {coverUrl ? (
        <>
          <img src={coverUrl} alt="" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
          <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(to bottom, rgba(0,0,0,.18) 0%, rgba(0,0,0,.52) 100%)' }} />
        </>
      ) : (
        <>
          <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(ellipse at 50% 40%, #f3cda0 0%, #c97e4a 50%, #6a3520 90%, #1f1208 100%)' }} />
          <div style={{ position: 'absolute', left: '38%', top: '30%', width: '24%', height: '55%', background: 'radial-gradient(ellipse at center, rgba(245,225,195,.7) 0%, transparent 70%)' }} />
          <div className="film-leak-tl" />
          <div className="film-leak-br" />
          <div className="film-vignette" />
          <svg className="film-grain" preserveAspectRatio="none" style={{ position: 'absolute', inset: 0 }}>
            <rect width="100%" height="100%" filter="url(#grain)" />
          </svg>
        </>
      )}
      {children}
    </div>
  )
}

// ── Step 1: Landing ──────────────────────────────────────────────────────────
function LandingStep({ preview, onNext }: { preview: EventPreview | null; onNext: () => void }) {
  const isDraft = preview?.status === 'draft'
  const isCompleted = preview?.status === 'completed' || preview?.status === 'cancelled'

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', position: 'relative' }}>
      {/* Hero */}
      <div style={{ height: 320, margin: '12px 16px 0', borderRadius: 24, overflow: 'hidden', position: 'relative', flexShrink: 0 }}>
        <FilmHero coverUrl={preview?.cover_url}>
          {preview?.status === 'active' && (
            <div style={{
              position: 'absolute', left: 16, top: 14,
              height: 26, padding: '0 10px',
              background: 'rgba(0,0,0,.4)', backdropFilter: 'blur(8px)',
              color: 'var(--paper)', borderRadius: 999,
              fontSize: 11, fontWeight: 600, fontFamily: 'Inter, sans-serif',
              letterSpacing: '.12em', display: 'inline-flex', alignItems: 'center', gap: 6,
            }}>
              <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--shutter)', display: 'inline-block' }} />
              ИДЁТ
            </div>
          )}
          {isCompleted && (
            <div style={{
              position: 'absolute', left: 16, top: 14,
              height: 26, padding: '0 10px',
              background: 'rgba(0,0,0,.5)', backdropFilter: 'blur(8px)',
              color: 'rgba(240,230,210,.7)', borderRadius: 999,
              fontSize: 11, fontFamily: 'Inter, sans-serif',
              letterSpacing: '.12em', display: 'inline-flex', alignItems: 'center', gap: 6,
            }}>
              ЗАВЕРШЕНО
            </div>
          )}
        </FilmHero>
      </div>

      {/* Copy */}
      <div style={{ padding: '18px 24px 0' }}>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase' }}>
          {isCompleted ? 'Мероприятие завершено' : 'Вас пригласили'}
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 38, lineHeight: 1, letterSpacing: '-.02em', margin: '8px 0 6px' }}>
          {preview?.title ?? '...'}
        </h1>
        {preview?.reveal_at && !isCompleted && (
          <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 12, letterSpacing: '.08em', color: 'var(--ink-3)', marginBottom: 18 }}>
            ОТКРОЕТСЯ В {revealLabel(preview.reveal_at)}
          </div>
        )}

        {/* Meta grid */}
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 1fr 1fr',
          borderRadius: 16, background: 'var(--paper-2)', padding: '14px 0', marginTop: preview?.reveal_at && !isCompleted ? 0 : 18,
        }}>
          {[
            { v: preview ? String(preview.frames_per_guest) : '—', l: 'Кадра' },
            { v: revealLabel(preview?.reveal_at ?? null), l: 'Откроется' },
            { v: preview ? filmLabel(preview.lut_preset) : '—', l: 'Плёнка' },
          ].map((item, i) => (
            <div key={i} style={{ textAlign: 'center', position: 'relative' }}>
              {i > 0 && <div style={{ position: 'absolute', left: 0, top: 8, bottom: 8, width: 1, background: 'var(--line)' }} />}
              <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 20, fontWeight: 500, color: 'var(--ink)', lineHeight: 1 }}>{item.v}</div>
              <div style={{ fontSize: 10, letterSpacing: '.12em', color: 'var(--ink-3)', textTransform: 'uppercase', marginTop: 5, fontFamily: 'Inter, sans-serif' }}>{item.l}</div>
            </div>
          ))}
        </div>
      </div>

      {/* CTA */}
      <div className="footer-gradient">
        {isCompleted ? (
          <div style={{ textAlign: 'center', padding: '0 24px' }}>
            <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.14em', color: 'var(--ink-3)', textTransform: 'uppercase', marginBottom: 8 }}>
              АЛЬБОМ ЗАКРЫТ
            </div>
            <div style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5 }}>
              Съёмка завершена. Если вы участвовали — попросите организатора прислать ссылку на альбом.
            </div>
          </div>
        ) : isDraft ? (
          <div style={{ textAlign: 'center', padding: '0 24px' }}>
            <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.14em', color: 'var(--amber)', textTransform: 'uppercase', marginBottom: 8 }}>
              СКОРО
            </div>
            <div style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5 }}>
              Мероприятие ещё не началось. Организатор откроет альбом немного позже.
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
  useEffect(() => {
    const t = setTimeout(() => inputRef.current?.focus(), 100)
    return () => clearTimeout(t)
  }, [])

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
      {/* Back link */}
      <button onClick={onBack} style={{ padding: '14px 24px 0', display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', letterSpacing: '.04em', background: 'none', border: 'none', cursor: 'pointer', alignSelf: 'flex-start', flexShrink: 0 }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 6 9 12 15 18"/></svg>
        {eventTitle || 'Назад'}
      </button>

      {/* Main content — grows, no overflow */}
      <div style={{ flex: 1, padding: '20px 24px 0', display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase' }}>
          Шаг 1 из 2
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 36, lineHeight: 1.05, letterSpacing: '-.02em', margin: '8px 0 6px' }}>
          Как вас<br />подписать?
        </h1>
        <p style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5, margin: '0 0 20px' }}>
          Имя появится под каждым вашим кадром в общем альбоме. Можно псевдоним.
        </p>

        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 10, letterSpacing: '.14em', color: 'var(--ink-3)', textTransform: 'uppercase', marginBottom: 8 }}>
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
          style={{ flexShrink: 0 }}
        />
        {error && <p style={{ color: 'var(--shutter)', fontSize: 13, marginTop: 8 }}>{error}</p>}

        <p style={{ fontSize: 11, color: 'var(--ink-4)', marginTop: 12, lineHeight: 1.5 }}>
          Гостю не нужен аккаунт. Имя видят только организатор и&nbsp;участники.
        </p>
      </div>

      {/* Button — always visible at bottom, doesn't overlap content */}
      <div style={{ padding: '16px 20px', paddingBottom: 'max(env(safe-area-inset-bottom, 16px), 16px)', background: 'var(--paper)', flexShrink: 0 }}>
        <button className="btn" onClick={onNext} disabled={loading || !name.trim()}>
          {loading ? 'Входим...' : 'Дальше'}
          {!loading && <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="13 6 19 12 13 18"/></svg>}
        </button>
      </div>
    </div>
  )
}

// ── Step 2a: Consent (согласия по 152-ФЗ, до присоединения) ──────────────────
function ConsentStep({
  eventTitle, onBack, onNext, loading, error,
}: {
  eventTitle: string; onBack: () => void; onNext: () => void;
  loading: boolean; error: string | null;
}) {
  const [offer, setOffer] = useState(false)
  const [privacy, setPrivacy] = useState(false)
  const [consent, setConsent] = useState(false)
  const [rules, setRules] = useState(false)
  const [age, setAge] = useState(false)
  const allChecked = offer && privacy && consent && rules && age

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
      <button onClick={onBack} style={{ padding: '14px 24px 0', display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', letterSpacing: '.04em', background: 'none', border: 'none', cursor: 'pointer', alignSelf: 'flex-start', flexShrink: 0 }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 6 9 12 15 18"/></svg>
        {eventTitle || 'Назад'}
      </button>

      <div style={{ flex: 1, padding: '20px 24px 0', display: 'flex', flexDirection: 'column', minHeight: 0, overflowY: 'auto' }}>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase' }}>
          Шаг 2 из 2
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 32, lineHeight: 1.1, letterSpacing: '-.02em', margin: '8px 0 6px' }}>
          Немного<br />формальностей
        </h1>
        <p style={{ fontSize: 13, color: 'var(--ink-3)', lineHeight: 1.5, margin: '0 0 20px' }}>
          Отметьте, что ознакомились с четырьмя документами. Каждый открывается по клику.
        </p>

        <ConsentRow
          checked={offer} onToggle={() => setOffer(v => !v)}
          title="Публичная оферта" subtitle="Условия использования сервиса"
          link="/offer"
        />
        <ConsentRow
          checked={privacy} onToggle={() => setPrivacy(v => !v)}
          title="Политика конфиденциальности" subtitle="Какие данные мы обрабатываем"
          link="/privacy"
        />
        <ConsentRow
          checked={consent} onToggle={() => setConsent(v => !v)}
          title="Согласие на обработку ПД" subtitle="Отдельный документ по 152-ФЗ"
          link="/consent"
        />
        <ConsentRow
          checked={rules} onToggle={() => setRules(v => !v)}
          title="Правила пользовательского контента" subtitle="Что можно и нельзя загружать"
          link="/content-rules"
        />
        <ConsentRow
          checked={age} onToggle={() => setAge(v => !v)}
          title="Мне исполнилось 14 лет" subtitle="Подтверждаю самостоятельно"
        />

        {error && <p style={{ color: 'var(--shutter)', fontSize: 13, marginTop: 8 }}>{error}</p>}
      </div>

      <div style={{ padding: '16px 20px', paddingBottom: 'max(env(safe-area-inset-bottom, 16px), 16px)', background: 'var(--paper)', flexShrink: 0 }}>
        <button className="btn" onClick={onNext} disabled={loading || !allChecked}>
          {loading ? 'Сохраняем...' : 'Продолжить'}
          {!loading && <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="13 6 19 12 13 18"/></svg>}
        </button>
      </div>
    </div>
  )
}

function ConsentRow({ checked, onToggle, title, subtitle, link }: {
  checked: boolean; onToggle: () => void; title: string; subtitle: string; link?: string;
}) {
  return (
    <div
      onClick={onToggle}
      style={{
        display: 'flex', gap: 12, alignItems: 'flex-start',
        padding: '10px 12px', marginBottom: 10, borderRadius: 12, cursor: 'pointer',
        background: checked ? 'rgba(201,136,30,0.06)' : 'var(--paper-2)',
        border: `1px solid ${checked ? 'rgba(201,136,30,0.30)' : 'var(--line)'}`,
      }}
    >
      <input
        type="checkbox"
        checked={checked}
        onChange={onToggle}
        onClick={(e) => e.stopPropagation()}
        style={{ marginTop: 3, width: 18, height: 18, accentColor: 'var(--amber)', flexShrink: 0 }}
      />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
          <div style={{ fontSize: 14, fontWeight: 600, color: 'var(--ink)' }}>{title}</div>
          {link && (
            <a
              href={link}
              target="_blank"
              rel="noopener noreferrer"
              onClick={(e) => e.stopPropagation()}
              style={{ fontSize: 11, color: 'var(--amber)', fontWeight: 500, textDecoration: 'none', whiteSpace: 'nowrap' }}
            >
              открыть →
            </a>
          )}
        </div>
        <div style={{ fontSize: 12, color: 'var(--ink-3)', lineHeight: 1.4, marginTop: 2 }}>{subtitle}</div>
      </div>
    </div>
  )
}

// ── Step 2b: PIN entry (only if event has pin_enabled) ──────────────────────
function PinStep({
  eventTitle, pin, onChange, onBack, onSubmit, loading, error, prefilledPin, onAutoSubmit,
}: {
  eventTitle: string; pin: string; onChange: (v: string) => void;
  onBack: () => void; onSubmit: () => void; loading: boolean; error: string | null;
  prefilledPin?: string; onAutoSubmit: (p: string) => void;
}) {
  const inputRefs = [useRef<HTMLInputElement>(null), useRef<HTMLInputElement>(null), useRef<HTMLInputElement>(null), useRef<HTMLInputElement>(null)]

  // Auto-focus first cell, auto-submit если pin пришёл из URL ?p=
  useEffect(() => {
    inputRefs[0].current?.focus()
    if (prefilledPin && /^\d{4}$/.test(prefilledPin)) {
      onAutoSubmit(prefilledPin)
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const digits = pin.padEnd(4, ' ').split('').map((c) => c.trim())

  const handleCellChange = (i: number, v: string) => {
    const digit = v.replace(/\D/g, '').slice(0, 1)
    const arr = digits.slice()
    arr[i] = digit
    const newPin = arr.join('').replace(/\s/g, '')
    onChange(newPin)
    if (digit && i < 3) inputRefs[i + 1].current?.focus()
    if (digit && i === 3 && newPin.length === 4) {
      inputRefs[3].current?.blur()
      // auto-submit
      setTimeout(() => onSubmit(), 50)
    }
  }
  const handleKey = (i: number, e: React.KeyboardEvent<HTMLInputElement>) => {
    if (e.key === 'Backspace' && !digits[i] && i > 0) {
      inputRefs[i - 1].current?.focus()
    }
  }
  const handlePaste = (e: React.ClipboardEvent<HTMLInputElement>) => {
    const txt = e.clipboardData.getData('text').replace(/\D/g, '').slice(0, 4)
    if (txt.length === 4) {
      e.preventDefault()
      onChange(txt)
      inputRefs[3].current?.blur()
      setTimeout(() => onSubmit(), 50)
    }
  }

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
      <button onClick={onBack} style={{ padding: '14px 24px 0', display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', letterSpacing: '.04em', background: 'none', border: 'none', cursor: 'pointer', alignSelf: 'flex-start', flexShrink: 0 }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 6 9 12 15 18"/></svg>
        Назад
      </button>

      <div style={{ flex: 1, padding: '20px 24px 0', display: 'flex', flexDirection: 'column', minHeight: 0 }}>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase' }}>
          PIN события
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 32, lineHeight: 1.05, letterSpacing: '-.02em', margin: '8px 0 6px' }}>
          Введите PIN
        </h1>
        <p style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5, margin: '0 0 20px' }}>
          {eventTitle ? `«${eventTitle}» защищён 4-значным PIN.` : 'Событие защищено 4-значным PIN.'} Спросите у организатора.
        </p>

        <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
          {[0, 1, 2, 3].map((i) => (
            <input
              key={i}
              ref={inputRefs[i]}
              type="tel"
              inputMode="numeric"
              maxLength={1}
              value={digits[i] || ''}
              onChange={(e) => handleCellChange(i, e.target.value)}
              onKeyDown={(e) => handleKey(i, e)}
              onPaste={handlePaste}
              disabled={loading}
              style={{
                flex: 1, textAlign: 'center', fontFamily: 'Inter, sans-serif',
                fontSize: 24, fontWeight: 700, padding: '18px 0',
                borderRadius: 10, background: 'var(--paper)',
                border: `1.5px solid ${error ? 'var(--shutter)' : (digits[i] ? 'var(--amber)' : 'rgba(26,23,20,.13)')}`,
                color: digits[i] ? 'var(--amber)' : 'var(--ink)',
              }}
            />
          ))}
        </div>
        {error && <p style={{ color: 'var(--shutter)', fontSize: 13, marginTop: 14 }}>{error}</p>}
      </div>

      <div style={{ padding: '16px 20px', paddingBottom: 'max(env(safe-area-inset-bottom, 16px), 16px)', background: 'var(--paper)', flexShrink: 0 }}>
        <button
          className="btn"
          onClick={onSubmit}
          disabled={loading || pin.length !== 4}
        >
          {loading ? 'Проверяем...' : 'Войти в альбом'}
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
      <button onClick={onBack} style={{ padding: '12px 24px 0', display: 'flex', alignItems: 'center', gap: 8, fontSize: 13, color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', letterSpacing: '.04em', background: 'none', border: 'none', cursor: 'pointer', alignSelf: 'flex-start' }}>
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="15 6 9 12 15 18"/></svg>
        {guestName} · {eventTitle || 'Назад'}
      </button>

      <div style={{ padding: '24px 24px 0' }}>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase' }}>
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
            Только для этого мероприятия
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

function restoreSession(shortCode: string): boolean {
  const token = localStorage.getItem(`gt_${shortCode}`)
  if (!token) return false
  sessionStorage.setItem('guest_token', token)
  const id = localStorage.getItem(`gi_${shortCode}`)
  const name = localStorage.getItem(`gn_${shortCode}`)
  const ev = localStorage.getItem(`ge_${shortCode}`)
  if (id) sessionStorage.setItem('guest_id', id)
  if (name) sessionStorage.setItem('guest_name', name)
  if (ev) sessionStorage.setItem('event', ev)
  return true
}

// ── Main component ───────────────────────────────────────────────────────────
export default function LandingScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const [urlSearch] = useState(() => new URLSearchParams(window.location.search))
  const prefilledPin = urlSearch.get('p') || undefined
  const navigate = useNavigate()
  const [step, setStep] = useState<'landing' | 'name' | 'consent' | 'pin' | 'permission'>('landing')
  const [name, setName] = useState('')
  const [pin, setPin] = useState('')
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [preview, setPreview] = useState<EventPreview | null>(null)

  useEffect(() => {
    if (!shortCode) return
    // Returning guest: restore session from localStorage and auto-redirect
    if (restoreSession(shortCode)) {
      api.get<EventPreview>(`/guest/events/${shortCode}`)
        .then(({ data }) => {
          if (data.status === 'completed' || data.status === 'cancelled') {
            navigate(`/g/${shortCode}/album`, { replace: true })
          } else if (data.start_at && new Date(data.start_at) > new Date()) {
            navigate(`/g/${shortCode}/not-started`, { replace: true })
          } else {
            navigate(`/g/${shortCode}/camera`, { replace: true })
          }
        })
        .catch((e) => { console.error('session_restore_failed', e); navigate(`/g/${shortCode}/camera`, { replace: true }) })
      return
    }
    // First-time guest: fetch event preview for landing page
    api.get<EventPreview>(`/guest/events/${shortCode}`)
      .then(({ data }) => setPreview(data))
      .catch((e) => console.error('event_preview_failed', e))
  }, [shortCode]) // eslint-disable-line react-hooks/exhaustive-deps

  const handleJoin = async (pinOverride?: string) => {
    if (!name.trim() || !shortCode) return
    setLoading(true)
    setError(null)
    const effectivePin = pinOverride ?? pin
    try {
      const { data } = await guestApi.createSession(
        shortCode, name.trim(), effectivePin || undefined
      )
      saveSession(shortCode, data.guest_token, data.guest_id, name.trim(), data.event)
      setStep('permission')
    } catch (err: unknown) {
      const e = err as { response?: { status?: number; data?: { error?: { code?: string; message?: string; details?: Record<string, unknown> }; detail?: string } } }
      const status = e?.response?.status
      const errCode = e?.response?.data?.error?.code
      const backendMsg = e?.response?.data?.error?.message ?? e?.response?.data?.detail ?? ''
      // PIN flow: 400 + code=PIN_REQUIRED → показать PIN-экран
      if (status === 400 && errCode === 'PIN_REQUIRED') {
        setStep('pin')
        setLoading(false)
        return
      }
      // BAD_PIN — оставляем на PIN-экране, показываем ошибку
      if (status === 400 && errCode === 'BAD_PIN') {
        setError('Неверный PIN. Проверьте у организатора.')
        setPin('')
        setLoading(false)
        return
      }
      if (status === 429 && errCode === 'RATE_LIMITED') {
        setError('Слишком много попыток. Попробуйте через час.')
        setLoading(false)
        return
      }
      if (status === 429 && errCode === 'ALBUM_CAP') {
        setError('Вы вошли в 3 альбома за сутки — это лимит защиты от перебора.')
        setLoading(false)
        return
      }
      if (status === 409) {
        // Refetch preview so landing shows fresh status/max_guests state.
        try {
          const { data: fresh } = await api.get<EventPreview>(`/guest/events/${shortCode}`)
          setPreview(fresh)
        } catch {}
        // Categorise the error for a human message.
        const details = e?.response?.data?.error?.details ?? {}
        const msg = String(backendMsg)
        if (/лимит|limit/i.test(msg) || 'max_guests' in details) {
          setError('Достигнут лимит гостей на этом альбоме. Попроси хоста расширить.')
          setLoading(false)
          return
        }
        if (/не начал/i.test(msg) || 'start_at' in details) {
          navigate(`/g/${shortCode}/not-started`, { replace: true })
          return
        }
        if (/заверш|закрыт/i.test(msg) || (typeof (details as Record<string, unknown>).status === 'string' && ['completed', 'cancelled'].includes(String((details as Record<string, unknown>).status)))) {
          setError('Альбом уже закрыт. Если у вас есть публичная ссылка от хоста — откройте её.')
          setStep('landing')
          setLoading(false)
          return
        }
        setError(msg || 'Не удалось войти в альбом.')
        setLoading(false)
        return
      }
      setError(backendMsg || 'Не удалось войти. Попробуйте ещё раз.')
    } finally {
      setLoading(false)
    }
  }

  const handleAcceptConsents = async () => {
    setLoading(true)
    setError(null)
    try {
      const CONSENT_VERSION = '2.0'
      const docs: Array<'offer' | 'privacy' | 'consent' | 'content_rules'> = [
        'offer', 'privacy', 'consent', 'content_rules',
      ]
      for (const docType of docs) {
        await guestApi.acceptConsent(docType, CONSENT_VERSION)
      }
      // Помечаем локально, чтобы при повторных заходах не показывать снова.
      try { localStorage.setItem('im_consent_v2_accepted', '1') } catch {}
      await handleJoin()
    } catch (e) {
      console.error('accept_consents_failed', e)
      setError('Не удалось сохранить согласия. Попробуйте ещё раз.')
      setLoading(false)
    }
  }

  const goAfterName = () => {
    // Если гость уже принял актуальную версию согласий — пропускаем экран.
    let alreadyAccepted = false
    try { alreadyAccepted = localStorage.getItem('im_consent_v2_accepted') === '1' } catch {}
    if (alreadyAccepted) return handleJoin()
    setStep('consent')
  }

  if (step === 'landing') return <LandingStep preview={preview} onNext={() => setStep('name')} />
  if (step === 'name') return (
    <NameStep
      eventTitle={preview?.title ?? ''}
      name={name} onChange={setName}
      onBack={() => setStep('landing')}
      onNext={goAfterName}
      loading={loading} error={error}
    />
  )
  if (step === 'consent') return (
    <ConsentStep
      eventTitle={preview?.title ?? ''}
      onBack={() => setStep('name')}
      onNext={handleAcceptConsents}
      loading={loading} error={error}
    />
  )
  if (step === 'pin') return (
    <PinStep
      eventTitle={preview?.title ?? ''}
      pin={pin} onChange={setPin}
      onBack={() => setStep('name')}
      onSubmit={() => handleJoin(pin)}
      loading={loading} error={error}
      prefilledPin={prefilledPin}
      onAutoSubmit={(p) => { setPin(p); handleJoin(p) }}
    />
  )
  return (
    <PermissionStep
      eventTitle={preview?.title ?? ''}
      guestName={name}
      onBack={() => setStep('name')}
      onAllow={() => {
        try {
          const ev = JSON.parse(sessionStorage.getItem('event') ?? '{}')
          if (ev.start_at && new Date(ev.start_at) > new Date()) {
            navigate(`/g/${shortCode}/not-started`)
            return
          }
        } catch {}
        navigate(`/g/${shortCode}/camera`)
      }}
    />
  )
}
