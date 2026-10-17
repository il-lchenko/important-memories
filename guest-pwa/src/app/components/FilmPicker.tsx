import { FILM_LABELS } from '../format'

/** Те же цветовые матрицы, что в превью приложения (create_event_screen.dart). */
const MATRIX: Record<string, string> = {
  original: '1 0 0 0 0  0 1 0 0 0  0 0 1 0 0  0 0 0 1 0',
  portra400: '1.12 0.08 -0.05 0 0  0 1.05 0 0 0  0 -0.05 0.85 0 0  0 0 0 1 0',
  fuji400h: '0.88 0 0.05 0 0  0.04 1.1 0 0 0  0 0.06 0.98 0 0  0 0 0 1 0',
  cinestill: '1.18 0.08 0 0 0  0 0.88 0 0 0  0.1 0 0.8 0 0  0 0 0 1 0',
  ilford: '0.2126 0.7152 0.0722 0 0  0.2126 0.7152 0.0722 0 0  0.2126 0.7152 0.0722 0 0  0 0 0 1 0',
}

const ORDER = ['original', 'portra400', 'fuji400h', 'cinestill', 'ilford'] as const
export type FilmId = (typeof ORDER)[number]

/** Выбор плёнки: карточка с примером кадра, названием и описанием; по умолчанию «Без фильтра». */
export function FilmPicker({ value, onChange }: { value: string; onChange: (id: FilmId) => void }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <svg width="0" height="0" style={{ position: 'absolute' }} aria-hidden="true">
        <defs>
          {ORDER.map((id) => (
            <filter key={id} id={`film-${id}`} colorInterpolationFilters="sRGB">
              <feColorMatrix type="matrix" values={MATRIX[id]} />
            </filter>
          ))}
        </defs>
      </svg>
      {ORDER.map((id) => {
        const active = value === id
        const f = FILM_LABELS[id]
        return (
          <button key={id} type="button" onClick={() => onChange(id)} aria-pressed={active}
            style={{
              display: 'flex', alignItems: 'stretch', height: 100, padding: 0, textAlign: 'left', cursor: 'pointer', overflow: 'hidden',
              borderRadius: 16, fontFamily: 'inherit', color: 'inherit',
              background: active ? 'rgba(201,136,30,.06)' : 'var(--paper-2)',
              border: active ? '2px solid var(--amber)' : '1px solid var(--line)',
              boxShadow: active ? '0 0 12px rgba(201,136,30,.18)' : 'none',
            }}>
            <div style={{ width: 90, flexShrink: 0, overflow: 'hidden', background: 'var(--paper-3)' }}>
              <img src="/hero/6.jpg" alt="" loading="lazy" draggable={false}
                style={{ width: '100%', height: '100%', objectFit: 'cover', objectPosition: '84% 52%', filter: `url(#film-${id})`, display: 'block' }} />
            </div>
            <div style={{ flex: 1, minWidth: 0, padding: '14px 8px 14px 16px', display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
              <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 17, fontWeight: 700, lineHeight: 1.15, color: active ? 'var(--ink)' : 'var(--ink-2, #4a4238)' }}>{f.name}</div>
              <div style={{ marginTop: 5, fontFamily: 'Inter, sans-serif', fontSize: 12, lineHeight: 1.4, color: 'var(--ink-3)' }}>{f.desc}</div>
            </div>
            <div style={{ display: 'flex', alignItems: 'center', paddingRight: 14, color: active ? 'var(--amber)' : 'transparent' }}>
              <svg width="20" height="20" viewBox="0 0 24 24" aria-hidden="true"><path fill="currentColor" d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm-2 15l-5-5 1.41-1.41L10 14.17l7.59-7.59L19 8l-9 9z" /></svg>
            </div>
          </button>
        )
      })}
    </div>
  )
}
