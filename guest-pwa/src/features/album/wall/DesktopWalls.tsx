import { useMemo, useRef, type CSSProperties } from 'react'
import { PolaroidCaption, UploadBadge, type Frame, type ViewMode } from '../AlbumScreen'
import { WallImage } from './WallImage'
import { aspectOf, hash32, justifyRows, rng, useElementWidth } from './useWall'
import './wall.css'

interface WallProps {
  frames: Frame[]
  eventId: string
  onOpenFrame: (i: number) => void
}

const keyOpen = (open: () => void) => (e: React.KeyboardEvent) => {
  if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); open() }
}

function HoverInfo({ frame }: { frame: Frame }) {
  const caption = (frame.caption ?? '').trim()
  return (
    <div className="wl-ov">
      <div className="wl-ov-av" style={frame.guest_avatar_url ? { background: `#2a1a10 center/cover no-repeat url(${frame.guest_avatar_url})` } : undefined}>
        {!frame.guest_avatar_url && (frame.guest_name?.[0]?.toUpperCase() ?? '?')}
      </div>
      <div className="wl-ov-tx">{caption || frame.guest_name}</div>
    </div>
  )
}

/* ── Журнал: ровная мозаика по реальным пропорциям кадров ── */
function Mosaic({ frames, onOpenFrame }: WallProps) {
  const ref = useRef<HTMLDivElement>(null)
  const W = useElementWidth(ref)
  const gap = 8
  const target = W >= 1500 ? 300 : W >= 1100 ? 270 : 230
  const rows = useMemo(() => justifyRows(frames, W, gap, () => target), [frames, W, target])
  return (
    <div ref={ref} className="wl-wrap">
      {rows.map((row, ri) => (
        <div key={ri} className="wl-row" style={{ gap, marginBottom: gap }}>
          {row.tiles.map((t) => (
            <div key={frames[t.i].id} className="wl-tile" style={{ width: t.w, height: t.h }} role="button" tabIndex={0} aria-label={`Кадр ${t.i + 1}`} onClick={() => onOpenFrame(t.i)} onKeyDown={keyOpen(() => onOpenFrame(t.i))}>
              <WallImage frame={frames[t.i]} w={t.w} h={t.h} index={t.i} />
              {frames[t.i].source === 'upload' && <UploadBadge />}
              <HoverInfo frame={frames[t.i]} />
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}

/* ── Ретро: скрапбук. Отпечатки разной высоты, скотч, лёгкие наклоны ── */
const TAPES = ['#C9881E', '#D54B3D', '#F6F2E8', '#7FA37A', '#6F8FB5']

function Scrapbook({ frames, eventId, onOpenFrame }: WallProps) {
  const ref = useRef<HTMLDivElement>(null)
  const W = useElementWidth(ref)
  const gap = 24
  const seed = hash32(eventId)
  const rows = useMemo(
    () => justifyRows(frames, W - 12, gap, (ri) => 200 + rng(seed + ri * 7919)() * (W >= 1300 ? 150 : 110)),
    [frames, W, seed],
  )
  return (
    <div ref={ref} className="wl-wrap">
      {rows.map((row, ri) => (
        <div key={ri} className="wl-row" style={{ gap, marginBottom: 30, padding: '0 6px' }}>
          {row.tiles.map((t) => {
            const f = frames[t.i]
            const r = rng(hash32(f.id))
            const rot = (r() - 0.5) * 6
            const dy = (r() - 0.5) * 16
            const framed = r() < 0.5
            const tape = r() < 0.34 ? TAPES[Math.floor(r() * TAPES.length)] : null
            const pad = framed ? 8 : 0
            const caption = (f.caption ?? '').trim()
            const style = { width: t.w, height: t.h, padding: pad, background: framed ? '#FBF8F0' : undefined, '--r': `${rot}deg`, '--dy': `${dy}px`, '--tr': `${(r() - 0.5) * 8}deg` } as CSSProperties
            return (
              <div key={f.id} className="wl-scrap" style={style} role="button" tabIndex={0} aria-label={`Кадр ${t.i + 1}`} onClick={() => onOpenFrame(t.i)} onKeyDown={keyOpen(() => onOpenFrame(t.i))}>
                <div className="wl-scrap-in" style={{ width: t.w - pad * 2, height: t.h - pad * 2 }}>
                  <WallImage frame={f} w={t.w - pad * 2} h={t.h - pad * 2} index={t.i} />
                  {f.source === 'upload' && <UploadBadge />}
                  {caption && (
                    <div style={{
                      position: 'absolute', bottom: 8, left: 12, right: 12, textAlign: 'right', color: '#fff',
                      font: '19px/1.15 Caveat, cursive', textShadow: '0 1px 4px rgba(0,0,0,.75)',
                      display: '-webkit-box', WebkitBoxOrient: 'vertical', WebkitLineClamp: 2, overflow: 'hidden',
                    }}>{caption}</div>
                  )}
                  {!caption && <HoverInfo frame={f} />}
                </div>
                {tape && <div className="wl-tape" style={{ background: tape }} />}
              </div>
            )
          })}
        </div>
      ))}
    </div>
  )
}

/* ── Полароид: стол с рассыпанными карточками (колонки без выравнивания по рядам) ── */
function PolaroidTable({ frames, eventId, onOpenFrame }: WallProps) {
  const ref = useRef<HTMLDivElement>(null)
  const W = useElementWidth(ref)
  const cols = W ? Math.max(3, Math.min(7, Math.floor(W / 280))) : 3
  const colW = W / cols
  const seed = hash32(eventId)

  const columns = useMemo(() => {
    const heights = new Array(cols).fill(0)
    const out: { i: number; cardW: number; ml: number; mt: number; rot: number; z: number; pin: string | null }[][] =
      Array.from({ length: cols }, () => [])
    frames.forEach((f, i) => {
      const r = rng(hash32(f.id) ^ seed)
      const cardW = colW * (0.76 + r() * 0.16)
      const ml = r() * Math.max(0, colW - cardW - 6)
      const mt = 14 - r() * 12
      const rot = (r() - 0.5) * 11
      const z = 1 + Math.floor(r() * 3)
      const pin = r() < 0.12 ? ['#D54B3D', '#C9881E', '#4F7DB3'][Math.floor(r() * 3)] : null
      const ratio = Math.min(1.25, Math.max(0.8, aspectOf(f)))
      const est = (cardW - 28) / ratio + 14 + ((f.caption ?? '').trim() ? 84 : 48) + mt
      let k = 0
      for (let c = 1; c < cols; c++) if (heights[c] < heights[k] - 1) k = c
      heights[k] += est
      out[k].push({ i, cardW, ml, mt, rot, z, pin })
    })
    return out
  }, [frames, cols, colW, seed])

  return (
    <div ref={ref} className="wl-wrap" style={{ paddingTop: 20 }}>
      <div className="wl-pol-cols">
        {columns.map((col, ci) => (
          <div key={ci} className="wl-pol-col" style={{ width: colW }}>
            {col.map((p) => {
              const f = frames[p.i]
              const ratio = Math.min(1.25, Math.max(0.8, aspectOf(f)))
              const photoW = p.cardW - 28
              const photoH = photoW / ratio
              const style = { width: p.cardW, marginLeft: p.ml, marginTop: p.mt, zIndex: p.z, '--r': `${p.rot}deg`, '--pin': p.pin ?? undefined } as CSSProperties
              return (
                <div key={f.id} className="wl-pol" style={style} role="button" tabIndex={0} aria-label={`Кадр ${p.i + 1}`} onClick={() => onOpenFrame(p.i)} onKeyDown={keyOpen(() => onOpenFrame(p.i))}>
                  <div style={{ padding: '14px 14px 0' }}>
                    <div className="wl-pol-photo" style={{ width: photoW, height: photoH }}>
                      <WallImage frame={f} w={photoW} h={photoH} index={p.i} />
                      {f.source === 'upload' && <UploadBadge />}
                    </div>
                  </div>
                  <PolaroidCaption caption={f.caption} guestName={f.guest_name} capturedAt={f.captured_at} />
                  {p.pin && <div className="wl-pin" />}
                </div>
              )
            })}
          </div>
        ))}
      </div>
    </div>
  )
}

export function DesktopWall({ mode, ...props }: WallProps & { mode: ViewMode }) {
  if (mode === 'retro') return <Scrapbook {...props} />
  if (mode === 'polaroid') return <PolaroidTable {...props} />
  return <Mosaic {...props} />
}
