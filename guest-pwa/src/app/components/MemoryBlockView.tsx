import type { CSSProperties } from 'react'
import { Link } from 'react-router-dom'
import { EVENT_TYPE_LABELS, formatShortDate } from '../format'
import type { Schemas } from '../api/hostClient'

type Block = Schemas['MemoryBlock']
type Thumb = Block['thumbs'][number]

const IMG: CSSProperties = { width: '100%', height: '100%', objectFit: 'cover', display: 'block' }

function Pic({ t, style }: { t: Thumb | undefined; style?: CSSProperties }) {
  if (!t) return <div style={{ background: 'var(--paper-3)', borderRadius: 12, ...style }} />
  return (
    <div style={{ overflow: 'hidden', borderRadius: 12, background: '#1A1714', ...style }}>
      <img src={t.url} alt="" loading="lazy" draggable={false}
        style={{ ...IMG, transform: t.rotation ? `rotate(${t.rotation}deg) scale(${t.rotation % 180 ? 1.34 : 1})` : undefined }} />
    </div>
  )
}

/** Раскладки подборок «Кадров»: веер, коллажи и сетка, как в приложении. */
function Layout({ type, thumbs }: { type: Block['type']; thumbs: Thumb[] }) {
  const t = thumbs
  const grid = (cols: string, rows: string, areas: string, count: number, ratio: string) => (
    <div style={{ display: 'grid', gap: 6, gridTemplateColumns: cols, gridTemplateRows: rows, gridTemplateAreas: areas, aspectRatio: ratio }}>
      {Array.from({ length: count }, (_, i) => <Pic key={i} t={t[i]} style={{ gridArea: String.fromCharCode(97 + i), height: '100%' }} />)}
    </div>
  )
  switch (type) {
    case 'tilted': {
      const angles = [-7, -2, 3, 8]
      return (
        <div style={{ position: 'relative', height: 190, margin: '4px 6px 10px' }}>
          {t.slice(0, 4).map((th, i) => (
            <div key={th.frame_id} style={{
              position: 'absolute', top: 8 + (i % 2) * 6, left: `${i * 22}%`, width: '34%', aspectRatio: '3 / 4',
              transform: `rotate(${angles[i]}deg)`, background: '#fff', padding: 4, borderRadius: 6,
              boxShadow: '0 6px 16px rgba(26,23,20,.22)', zIndex: i,
            }}>
              <img src={th.url} alt="" loading="lazy" draggable={false} style={{ ...IMG, borderRadius: 3 }} />
            </div>
          ))}
        </div>
      )
    }
    case 'collage_a': return grid('2fr 1fr', '1fr 1fr', '"a b" "a c"', 3, '4 / 3')
    case 'collage_b': return grid('1fr 1fr', '1fr 1fr', '"a b" "c c"', 3, '4 / 3')
    case 'collage_c': return grid('1fr 1fr 1fr', '1fr 1fr', '"a b c" "a d c"', 4, '4 / 3')
    case 'collage_d': return grid('1fr 1fr 1fr', '2fr 1fr', '"a a a" "b c d"', 4, '4 / 3')
    case 'collage_e': return grid('1fr 1fr', '1fr 1fr 1fr', '"a b" "a c" "d d"', 4, '1 / 1')
    default: return grid('1fr 1fr 1fr', '1fr 1fr', '"a b c" "d e f"', 6, '3 / 2')
  }
}

export function MemoryBlockView({ b }: { b: Block }) {
  const target = b.event_id ?? b.event_ids[0]
  const head = (
    <div style={{ display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between', gap: 10, marginBottom: 10 }}>
      <div style={{ minWidth: 0 }}>
        <div className="host-edge">
          {b.kind === 'collection' ? `подборка · ${b.albums_count ?? b.event_ids.length} альбомов` : (b.event_type ? EVENT_TYPE_LABELS[b.event_type] ?? 'Событие' : 'Событие')}
        </div>
        <div className="host-frame-title" style={{ margin: '2px 0 0', fontSize: 22 }}>{b.title}</div>
      </div>
      {b.date_iso && <span className="host-muted" style={{ fontSize: 13, whiteSpace: 'nowrap' }}>{formatShortDate(b.date_iso)}</span>}
    </div>
  )
  const body = <Layout type={b.type} thumbs={b.thumbs} />
  return target ? (
    <Link to={`/app/events/${target}/album`} style={{ display: 'block', textDecoration: 'none', color: 'inherit' }}>
      {head}{body}
    </Link>
  ) : <div>{head}{body}</div>
}
