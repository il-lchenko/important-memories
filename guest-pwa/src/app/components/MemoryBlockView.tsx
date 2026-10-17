import { useRef, useState, type CSSProperties, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { EVENT_TYPE_LABELS } from '../format'
import type { Schemas } from '../api/hostClient'

type Block = Schemas['MemoryBlock']
type Thumb = Block['thumbs'][number]

const GAP = 4
const RADIUS = 6

function albumsWord(n: number): string {
  const m10 = n % 10
  const m100 = n % 100
  if (m10 === 1 && m100 !== 11) return `${n} альбом`
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return `${n} альбома`
  return `${n} альбомов`
}

function daysWord(n: number): string {
  const m10 = n % 10
  const m100 = n % 100
  if (m10 === 1 && m100 !== 11) return 'день'
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return 'дня'
  return 'дней'
}

/** Подпись справа от названия: число альбомов или «Сегодня / Вчера / N дней назад / дата». */
function rightLabel(b: Block): string {
  if (b.albums_count && b.albums_count > 0) return albumsWord(b.albums_count)
  if (!b.date_iso) return ''
  const dt = new Date(b.date_iso)
  if (Number.isNaN(dt.getTime())) return ''
  const now = new Date()
  const day = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
  const diff = Math.round((day(now) - day(dt)) / 86400000)
  if (diff <= 0) return 'Сегодня'
  if (diff === 1) return 'Вчера'
  if (diff < 7) return `${diff} ${daysWord(diff)} назад`
  const opts: Intl.DateTimeFormatOptions = dt.getFullYear() === now.getFullYear()
    ? { day: 'numeric', month: 'long' }
    : { day: 'numeric', month: 'long', year: 'numeric' }
  return new Intl.DateTimeFormat('ru-RU', opts).format(dt)
}

/** Плитка кадра: по нажатию открывает кадр в исходном альбоме. */
function Tile({ t, style, className }: { t: Thumb | undefined; style?: CSSProperties; className?: string }) {
  const base: CSSProperties = { position: 'relative', overflow: 'hidden', borderRadius: RADIUS, background: 'var(--paper-3)', containerType: 'size', ...style }
  if (!t) return <div className={className} style={base} />
  const turns = Math.round(((t.rotation ?? 0) % 360) / 90)
  const sideways = turns % 2 !== 0
  const img: CSSProperties = sideways
    ? { position: 'absolute', top: '50%', left: '50%', width: '100cqh', height: '100cqw', objectFit: 'cover', transform: `translate(-50%, -50%) rotate(${turns * 90}deg)` }
    : { position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', transform: turns ? `rotate(${turns * 90}deg)` : undefined }
  const inner = <img src={t.url} alt="" loading="lazy" draggable={false} style={img} />
  const to = t.event_id ? `/app/events/${t.event_id}/album${t.frame_id ? `?f=${t.frame_id}` : ''}` : null
  return to
    ? <Link to={to} className={className} style={{ display: 'block', ...base }}>{inner}</Link>
    : <div className={className} style={base}>{inner}</div>
}

/** Страницы по perPage кадров; неполные страницы не показываем (как в приложении). */
function Carousel({ thumbs, perPage, height, keepPartial, page }: {
  thumbs: Thumb[]; perPage: number; height: number; keepPartial?: boolean
  page: (ts: Thumb[], pageIndex: number) => ReactNode
}) {
  const pages: Thumb[][] = []
  for (let i = 0; i < thumbs.length; i += perPage) {
    const chunk = thumbs.slice(i, i + perPage)
    if (chunk.length < perPage && !keepPartial) break
    pages.push(chunk)
  }
  const [cur, setCur] = useState(0)
  const ref = useRef<HTMLDivElement>(null)
  if (pages.length === 0) return null
  return (
    <div>
      <div
        ref={ref}
        className="host-snap"
        onScroll={(e) => {
          const el = e.currentTarget
          setCur(Math.round(el.scrollLeft / el.clientWidth))
        }}
        style={{ display: 'flex', overflowX: 'auto', scrollSnapType: 'x mandatory', scrollbarWidth: 'none', height }}
      >
        {pages.map((ts, i) => (
          <div key={i} style={{ flex: '0 0 100%', scrollSnapAlign: 'start', height }}>{page(ts, i)}</div>
        ))}
      </div>
      {pages.length > 1 && (
        <div style={{ display: 'flex', justifyContent: 'center', gap: 5, marginTop: 10 }}>
          {pages.map((_, i) => (
            <span key={i} style={{
              width: i === cur ? 18 : 6, height: 6, borderRadius: 3, transition: 'width .2s',
              background: i === cur ? 'var(--amber)' : 'rgba(158,148,136,.4)',
            }} />
          ))}
        </div>
      )}
    </div>
  )
}

const fill: CSSProperties = { width: '100%', height: '100%' }

function mirrorOf(block: Block, pageIndex: number): boolean {
  const key = `${block.event_id ?? block.title ?? ''}`
  let h = 0
  for (let i = 0; i < key.length; i++) h = (h * 31 + key.charCodeAt(i)) | 0
  return ((h ^ pageIndex) & 1) === 1
}

function Layout({ block }: { block: Block }) {
  const t = block.thumbs
  const type = block.type === 'collage_c' ? 'collage_a' : block.type
  switch (type) {
    case 'collage_a':
      if (t.length < 3) return null
      return (
        <Carousel thumbs={t} perPage={3} height={200} page={(ts, pi) => {
          const big = <Tile key="big" t={ts[0]} style={{ ...fill, flex: 2 }} />
          const smalls = (
            <div key="smalls" style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: GAP }}>
              <Tile t={ts[1]} style={{ flex: 1 }} />
              <Tile t={ts[2]} style={{ flex: 1 }} />
            </div>
          )
          return <div style={{ display: 'flex', gap: GAP, height: '100%' }}>{mirrorOf(block, pi) ? [smalls, big] : [big, smalls]}</div>
        }} />
      )
    case 'collage_b':
      if (t.length < 4) return null
      return (
        <Carousel thumbs={t} perPage={4} height={200} page={(ts) => (
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gridTemplateRows: '1fr 1fr', gap: GAP, height: '100%' }}>
            {ts.map((th, i) => <Tile key={i} t={th} />)}
          </div>
        )} />
      )
    case 'collage_d':
      if (t.length < 5) return null
      return (
        <Carousel thumbs={t} perPage={5} height={220} page={(ts) => (
          <div style={{ position: 'relative', height: '100%' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gridTemplateRows: '1fr 1fr', gap: GAP, height: '100%' }}>
              {ts.slice(0, 4).map((th, i) => <Tile key={i} t={th} style={{ opacity: 0.85 }} />)}
            </div>
            <div style={{
              position: 'absolute', top: '16%', left: '19%', width: '62%', height: '68%', transform: 'rotate(-2deg)',
              borderRadius: RADIUS, border: '0.8px solid rgba(255,255,255,.5)', overflow: 'hidden',
              boxShadow: '0 8px 22px rgba(0,0,0,.4), 0 2px 4px rgba(0,0,0,.15)',
            }}>
              <Tile t={ts[4]} style={{ ...fill, borderRadius: 0 }} />
            </div>
          </div>
        )} />
      )
    case 'collage_e':
      if (t.length < 4) return null
      return (
        <Carousel thumbs={t} perPage={4} height={220} page={(ts) => (
          <div style={{ display: 'flex', gap: GAP, height: '100%' }}>
            <Tile t={ts[0]} style={{ flex: 8, height: '100%' }} />
            <div style={{ flex: 5, display: 'flex', flexDirection: 'column', gap: GAP }}>
              <Tile t={ts[1]} style={{ flex: 1 }} />
              <Tile t={ts[2]} style={{ flex: 1 }} />
              <Tile t={ts[3]} style={{ flex: 1 }} />
            </div>
          </div>
        )} />
      )
    case 'grid_6':
      if (t.length === 0) return null
      return (
        <Carousel thumbs={t} perPage={6} height={214} keepPartial page={(ts) => (
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gridTemplateRows: '1fr 1fr', gap: GAP, height: '100%' }}>
            {Array.from({ length: 6 }, (_, i) => ts[i] ? <Tile key={i} t={ts[i]} /> : <div key={i} />)}
          </div>
        )} />
      )
    default:
      return <Tilted thumbs={t} />
  }
}

const ROT = [-3, 1.4, -1, 2.6]
const DY = [-2, 3, -3, 2]

/** Наклонная лента в стиле Once: карточки 92×116 внахлёст, листается вбок. */
function Tilted({ thumbs }: { thumbs: Thumb[] }) {
  if (thumbs.length === 0) return <div style={{ height: 128 }} />
  return (
    <div className="host-snap" style={{ display: 'flex', overflowX: 'auto', padding: '6px 0', height: 132, scrollbarWidth: 'none' }}>
      {thumbs.map((th, i) => (
        <div key={th.frame_id ?? i} style={{
          flex: '0 0 92px', height: 116, marginLeft: i === 0 ? 0 : -8,
          transform: `translateY(${DY[i % 4]}px) rotate(${ROT[i % 4]}deg)`,
          borderRadius: 10, overflow: 'hidden', border: '0.5px solid rgba(255,255,255,.35)',
          boxShadow: '0 3px 8px rgba(0,0,0,.16), 0 1px 2px rgba(0,0,0,.08)',
        }}>
          <Tile t={th} style={{ ...fill, borderRadius: 10 }} />
        </div>
      ))}
    </div>
  )
}

export function MemoryBlockView({ b }: { b: Block }) {
  const target = b.event_id ?? b.event_ids[0]
  const label = rightLabel(b)
  const showType = b.kind === 'single' && !!b.event_type
  return (
    <section style={{ padding: '0 0 4px' }}>
      {showType && (
        <div style={{ fontWeight: 800, fontSize: 13, color: 'var(--amber)', letterSpacing: '.08em', marginBottom: 5, textTransform: 'uppercase' }}>
          {EVENT_TYPE_LABELS[b.event_type ?? ''] ?? b.event_type}
        </div>
      )}
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 10, marginBottom: 12 }}>
        {target ? (
          <Link to={`/app/events/${target}/album`} className="host-frame-title"
            style={{ flex: 1, minWidth: 0, margin: 0, fontSize: 22, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', textDecoration: 'none', color: 'inherit' }}>
            {b.title || 'Кадры'}
          </Link>
        ) : (
          <div className="host-frame-title" style={{ flex: 1, margin: 0, fontSize: 22 }}>{b.title || 'Кадры'}</div>
        )}
        {label && <span className="host-muted" style={{ fontSize: 13, fontWeight: 500, whiteSpace: 'nowrap' }}>{label}</span>}
      </div>
      <Layout block={b} />
    </section>
  )
}
