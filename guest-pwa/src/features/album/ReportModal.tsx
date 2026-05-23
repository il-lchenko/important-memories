import { useState } from 'react'
import { api } from '../../api/client'

interface Props { frameId: string; onClose: () => void }

const REASONS = [
  { id: 'nudity',   label: 'Обнажёнка' },
  { id: 'violence', label: 'Насилие' },
  { id: 'spam',     label: 'Спам' },
  { id: 'other',    label: 'Другое' },
]

export default function ReportModal({ frameId, onClose }: Props) {
  const [selected, setSelected] = useState<string | null>(null)
  const [comment, setComment] = useState('')
  const [loading, setLoading] = useState(false)
  const [done, setDone] = useState(false)
  const [error, setError] = useState(false)

  const handleSubmit = async () => {
    if (!selected) return
    setLoading(true)
    setError(false)
    try {
      await api.post('/reports/', { frame_id: frameId, category: selected, comment: comment || undefined })
      setDone(true)
    } catch {
      setError(true)
    } finally {
      setLoading(false)
    }
  }

  return (
    <>
      {/* Backdrop */}
      <div onClick={onClose} style={{ position: 'fixed', inset: 0, background: 'rgba(26,23,20,.5)', zIndex: 100 }} />

      {/* Sheet */}
      <div style={{
        position: 'fixed', bottom: 0, left: 0, right: 0,
        background: 'var(--paper)', borderRadius: '24px 24px 0 0',
        padding: '24px 20px 36px', zIndex: 101,
        boxShadow: '0 -20px 40px rgba(0,0,0,.4)',
      }}>
        <div style={{ width: 36, height: 4, borderRadius: 2, background: 'rgba(26,23,20,.2)', margin: '0 auto 18px' }} />

        {done ? (
          <div style={{ textAlign: 'center', padding: '16px 0 8px' }}>
            <div style={{ fontSize: 36, marginBottom: 12 }}>✓</div>
            <p style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontSize: 20, color: 'var(--ink)', margin: '0 0 8px' }}>Жалоба отправлена</p>
            <p style={{ fontFamily: 'Inter, sans-serif', fontSize: 14, color: 'var(--ink-3)', margin: '0 0 24px' }}>Мы рассмотрим её в течение 24 часов</p>
            <button className="btn-ghost btn-sm" style={{ width: 'auto', padding: '0 32px' }} onClick={onClose}>Закрыть</button>
          </div>
        ) : (
          <>
            <h2 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 24, margin: '0 0 6px', letterSpacing: '-.01em' }}>
              Сообщить о кадре
            </h2>
            <p style={{ fontFamily: 'Inter, sans-serif', fontSize: 13, color: 'var(--ink-3)', margin: '0 0 16px', lineHeight: 1.5 }}>
              Жалоба придёт хосту. Имя автора и ваше имя останутся скрыты.
            </p>

            {/* Chips */}
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginBottom: 14 }}>
              {REASONS.map((r) => (
                <button
                  key={r.id}
                  onClick={() => setSelected(r.id)}
                  style={{
                    height: 34, padding: '0 14px', borderRadius: 17,
                    display: 'inline-flex', alignItems: 'center', gap: 6,
                    fontSize: 13, fontWeight: 500, cursor: 'pointer',
                    background: selected === r.id ? 'var(--ink)' : 'var(--paper-2)',
                    border: `1px solid ${selected === r.id ? 'var(--ink)' : 'var(--line)'}`,
                    color: selected === r.id ? 'var(--paper)' : 'var(--ink-2)',
                    transition: 'background 0.15s, border-color 0.15s, color 0.15s',
                  }}
                >
                  {r.label}
                </button>
              ))}
            </div>

            {/* Comment textarea */}
            <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.14em', color: 'var(--ink-3)', textTransform: 'uppercase', marginBottom: 8 }}>
              Комментарий · необязательно
            </div>
            <textarea
              value={comment}
              onChange={(e) => setComment(e.target.value)}
              placeholder="Что не так с этим кадром?"
              rows={3}
              style={{
                width: '100%', borderRadius: 14,
                background: 'var(--paper-2)', border: '1px solid var(--line)',
                padding: '12px 14px', fontFamily: 'Inter, sans-serif', fontSize: 14,
                color: 'var(--ink)', resize: 'none', lineHeight: 1.5,
                marginBottom: 12, outline: 'none',
              }}
            />

            {error && (
              <p style={{ fontFamily: 'Inter, sans-serif', fontSize: 13, color: 'var(--shutter)', marginBottom: 12, textAlign: 'center' }}>
                Не удалось отправить. Попробуйте ещё раз.
              </p>
            )}

            {/* Action row */}
            <div style={{ display: 'flex', gap: 10 }}>
              <button className="btn-ghost btn-sm" style={{ flex: 1 }} onClick={onClose}>Отмена</button>
              <button
                onClick={handleSubmit}
                disabled={!selected || loading}
                style={{
                  flex: 2, height: 44, borderRadius: 14, border: 'none',
                  background: 'var(--shutter)', color: '#fff',
                  fontFamily: 'Inter, sans-serif', fontSize: 14, fontWeight: 600,
                  cursor: selected ? 'pointer' : 'not-allowed',
                  opacity: !selected || loading ? 0.5 : 1,
                  boxShadow: '0 4px 12px -2px rgba(213,75,61,.4)',
                }}
              >
                {loading ? '...' : 'Отправить жалобу'}
              </button>
            </div>
          </>
        )}
      </div>
    </>
  )
}
