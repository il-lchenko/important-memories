import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'

interface RecentEntry {
  shortCode: string
  title: string
  status: string
  coverUrl: string | null
}

function loadRecent(): RecentEntry[] {
  const entries: RecentEntry[] = []
  for (let i = 0; i < localStorage.length; i++) {
    const key = localStorage.key(i)
    if (!key?.startsWith('gt_')) continue
    const shortCode = key.slice(3)
    const ev = localStorage.getItem(`ge_${shortCode}`)
    if (!ev) continue
    try {
      const parsed = JSON.parse(ev)
      entries.push({
        shortCode,
        title: typeof parsed.title === 'string' ? parsed.title : shortCode,
        status: typeof parsed.status === 'string' ? parsed.status : 'active',
        coverUrl: typeof parsed.cover_url === 'string' ? parsed.cover_url : null,
      })
    } catch {
      // ignore corrupt entries
    }
  }
  return entries
}

function statusBadge(status: string) {
  if (status === 'active') return { label: 'ИДЁТ', color: 'var(--shutter)' }
  if (status === 'completed' || status === 'cancelled') return { label: 'ЗАВЕРШЕНО', color: 'rgba(240,230,210,.7)' }
  return { label: 'СКОРО', color: 'var(--amber)' }
}

function normalizeCode(raw: string): string {
  return raw.toUpperCase().replace(/[^A-Z0-9]/g, '').slice(0, 8)
}

export default function HomeScreen() {
  const navigate = useNavigate()
  const [code, setCode] = useState('')
  const recent = useMemo(loadRecent, [])

  const canGo = code.length >= 4
  const go = () => {
    if (!canGo) return
    navigate(`/g/${code}`)
  }

  return (
    <div style={{
      minHeight: '100dvh', background: 'var(--paper)',
      display: 'flex', flexDirection: 'column', position: 'relative',
    }}>
      {/* Brand header */}
      <div style={{ padding: '24px 24px 16px' }}>
        <div style={{
          fontFamily: 'Inter, sans-serif', fontSize: 11,
          letterSpacing: '.18em', color: 'var(--amber)', textTransform: 'uppercase',
        }}>
          IMPORTANT MEMORIES
        </div>
        <h1 style={{
          fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500,
          fontSize: 34, lineHeight: 1.05, letterSpacing: '-.02em', margin: '8px 0 6px',
        }}>
          Ваши плёнки
        </h1>
        <p style={{ fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5, margin: 0 }}>
          {recent.length > 0
            ? 'Откройте альбом или подключитесь к новому событию.'
            : 'Введите код приглашения или отсканируйте QR.'}
        </p>
      </div>

      {/* Recent events list */}
      <div style={{ flex: 1, overflowY: 'auto', padding: '8px 16px 180px' }}>
        {recent.length > 0 ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
            {recent.map((r) => {
              const badge = statusBadge(r.status)
              return (
                <button
                  key={r.shortCode}
                  onClick={() => navigate(`/g/${r.shortCode}`)}
                  style={{
                    appearance: 'none', border: 'none', textAlign: 'left',
                    background: 'var(--paper-2)', borderRadius: 16, padding: 0,
                    display: 'flex', alignItems: 'stretch', height: 84,
                    cursor: 'pointer', overflow: 'hidden',
                  }}
                >
                  <div style={{
                    width: 84, flexShrink: 0, position: 'relative',
                    background: r.coverUrl
                      ? `center / cover no-repeat url("${r.coverUrl}")`
                      : 'radial-gradient(ellipse at 50% 40%, #f3cda0 0%, #c97e4a 60%, #6a3520 100%)',
                  }} />
                  <div style={{
                    flex: 1, padding: '12px 14px',
                    display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
                  }}>
                    <div style={{
                      fontFamily: 'Fraunces, serif', fontStyle: 'italic',
                      fontWeight: 500, fontSize: 18, color: 'var(--ink)',
                      letterSpacing: '-.01em', overflow: 'hidden',
                      textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                    }}>
                      {r.title}
                    </div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                      <span style={{
                        fontFamily: 'Inter, sans-serif', fontSize: 10,
                        letterSpacing: '.14em', color: badge.color,
                      }}>
                        {badge.label}
                      </span>
                      <span style={{ color: 'var(--ink-4)', fontSize: 10 }}>•</span>
                      <span style={{
                        fontFamily: 'Inter, sans-serif', fontSize: 11,
                        color: 'var(--ink-3)', letterSpacing: '.08em',
                      }}>
                        {r.shortCode}
                      </span>
                    </div>
                  </div>
                  <div style={{
                    display: 'flex', alignItems: 'center', paddingRight: 14,
                    color: 'var(--ink-4)',
                  }}>
                    <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
                         stroke="currentColor" strokeWidth="2"
                         strokeLinecap="round" strokeLinejoin="round">
                      <polyline points="9 6 15 12 9 18" />
                    </svg>
                  </div>
                </button>
              )
            })}
          </div>
        ) : (
          <div style={{
            marginTop: 24, padding: '24px 20px',
            background: 'var(--paper-2)', borderRadius: 20,
            textAlign: 'center',
          }}>
            <div style={{
              width: 48, height: 48, borderRadius: 14,
              background: 'rgba(201,136,30,.12)', color: 'var(--amber)',
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              marginBottom: 14,
            }}>
              <svg width="24" height="24" viewBox="0 0 24 24" fill="none"
                   stroke="currentColor" strokeWidth="1.6"
                   strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="3" width="7" height="7" />
                <rect x="14" y="3" width="7" height="7" />
                <rect x="3" y="14" width="7" height="7" />
                <path d="M14 14h7v7h-7z" />
              </svg>
            </div>
            <div style={{
              fontFamily: 'Fraunces, serif', fontStyle: 'italic',
              fontSize: 20, color: 'var(--ink)', marginBottom: 6,
            }}>
              Здесь будут ваши плёнки
            </div>
            <div style={{ fontSize: 13, color: 'var(--ink-3)', lineHeight: 1.5 }}>
              Отсканируйте QR из приглашения<br />или введите код события ниже.
            </div>
          </div>
        )}
      </div>

      {/* Sticky bottom: code input + CTA */}
      <div className="footer-gradient" style={{ paddingTop: 32 }}>
        <div style={{
          fontFamily: 'Inter, sans-serif', fontSize: 10,
          letterSpacing: '.14em', color: 'var(--ink-3)',
          textTransform: 'uppercase', marginBottom: 8,
        }}>
          Код события
        </div>
        <input
          inputMode="text"
          autoCapitalize="characters"
          autoCorrect="off"
          spellCheck={false}
          className="input-display"
          placeholder="ABCD1234"
          value={code}
          onChange={(e) => setCode(normalizeCode(e.target.value))}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && canGo) go()
          }}
          maxLength={8}
          style={{
            fontFamily: 'Inter, sans-serif',
            letterSpacing: '.2em', textTransform: 'uppercase',
          }}
        />
        <button
          className="btn"
          onClick={go}
          disabled={!canGo}
          style={{ marginTop: 12 }}
        >
          Подключиться
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
               stroke="#fff" strokeWidth="2"
               strokeLinecap="round" strokeLinejoin="round">
            <line x1="5" y1="12" x2="19" y2="12" />
            <polyline points="13 6 19 12 13 18" />
          </svg>
        </button>
      </div>
    </div>
  )
}
