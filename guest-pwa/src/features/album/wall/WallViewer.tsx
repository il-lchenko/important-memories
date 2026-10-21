import { useEffect, useRef, useState } from 'react'
import type { Frame } from '../AlbumScreen'
import { ZoomPan } from '../ZoomPan'

function RotatedPhoto({ src, fullSrc, rotation }: { src: string; fullSrc: string | null; rotation: number }) {
  const ref = useRef<HTMLDivElement>(null)
  const [box, setBox] = useState({ w: 0, h: 0 })
  const [fullLoaded, setFullLoaded] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    const update = () => setBox({ w: el.clientWidth, h: el.clientHeight })
    update()
    const ro = new ResizeObserver(update)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])
  const sideways = rotation % 180 !== 0
  const style = sideways
    ? { position: 'absolute' as const, top: '50%', left: '50%', width: box.h, height: box.w, objectFit: 'contain' as const, transform: `translate(-50%, -50%) rotate(${rotation}deg)` }
    : { position: 'absolute' as const, inset: 0, width: '100%', height: '100%', objectFit: 'contain' as const, transform: rotation ? `rotate(${rotation}deg)` : undefined }
  return (
    <div ref={ref} style={{ position: 'relative', width: '100%', height: '100%' }}>
      <img src={src} alt="" draggable={false} style={style} />
      {fullSrc && (
        <img src={fullSrc} alt="" draggable={false} onLoad={() => setFullLoaded(true)}
          style={{ ...style, opacity: fullLoaded ? 1 : 0, transition: 'opacity .2s ease' }} />
      )}
    </div>
  )
}

const ico = { width: 20, height: 20, viewBox: '0 0 24 24', fill: 'none', stroke: 'currentColor', strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' } as const

function fmtDate(iso: string): string {
  try {
    return new Date(iso).toLocaleString('ru', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })
  } catch { return '' }
}

/**
 * Просмотр кадра поверх стены на широком экране: фото слева, подпись и действия справа,
 * внизу лента соседних кадров. Стена под ним остаётся на месте, поэтому после закрытия
 * экран возвращается к тому же месту прокрутки.
 */
export function WallViewer({ frames, index, total, onIndex, onClose, onNeedMore, onMore, shareTitle }: {
  frames: Frame[]
  index: number
  total: number
  onIndex: (i: number) => void
  onClose: () => void
  onNeedMore?: () => void
  onMore?: () => void
  shareTitle?: string
}) {
  const frame = frames[index]
  const stripRef = useRef<HTMLDivElement>(null)
  const [note, setNote] = useState<string | null>(null)

  const prev = () => { if (index > 0) onIndex(index - 1) }
  const next = () => { if (index < frames.length - 1) onIndex(index + 1) }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
      else if (e.key === 'ArrowLeft') prev()
      else if (e.key === 'ArrowRight') next()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  useEffect(() => {
    // Полоса прокрутки остаётся зарезервированной: иначе ширина страницы меняется и стена за кадром перестраивается.
    const prevOverflow = document.body.style.overflow
    const prevGutter = document.documentElement.style.scrollbarGutter
    document.documentElement.style.scrollbarGutter = 'stable'
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = prevOverflow
      document.documentElement.style.scrollbarGutter = prevGutter
    }
  }, [])

  useEffect(() => {
    if (index >= frames.length - 4) onNeedMore?.()
    for (const f of [frames[index - 1], frames[index + 1]]) {
      const u = f?.preview_url ?? f?.full_url
      if (u) { const im = new Image(); im.src = u }
    }
    const strip = stripRef.current
    const cur = strip?.querySelector<HTMLElement>('[data-cur="1"]')
    if (strip && cur) strip.scrollTo({ left: cur.offsetLeft - strip.clientWidth / 2 + cur.clientWidth / 2, behavior: 'smooth' })
  }, [index, frames, onNeedMore])

  useEffect(() => {
    if (!note) return
    const t = setTimeout(() => setNote(null), 1800)
    return () => clearTimeout(t)
  }, [note])

  if (!frame) return null
  const rotation = ((frame.rotation ?? 0) % 360 + 360) % 360
  const caption = (frame.caption ?? '').trim()

  const share = async () => {
    const url = frame.full_url
    if (navigator.share) {
      try { await navigator.share({ url, title: shareTitle }); return } catch (e) { if ((e as DOMException)?.name === 'AbortError') return }
    }
    try { await navigator.clipboard.writeText(url); setNote('Ссылка скопирована') } catch { setNote('Не удалось скопировать') }
  }

  const win = frames.slice(Math.max(0, index - 20), index + 21)
  const winStart = Math.max(0, index - 20)

  const btn: React.CSSProperties = {
    width: 44, height: 44, borderRadius: '50%', border: '1px solid rgba(240,230,210,.26)', background: 'rgba(255,255,255,.07)',
    color: '#F0E6D2', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0, textDecoration: 'none',
  }
  const action: React.CSSProperties = {
    display: 'flex', alignItems: 'center', gap: 10, height: 46, padding: '0 16px', borderRadius: 12, textDecoration: 'none',
    border: '1px solid rgba(240,230,210,.22)', background: 'rgba(255,255,255,.06)', color: '#F0E6D2',
    font: '600 14px Manrope, Inter, sans-serif', cursor: 'pointer',
  }

  return (
    <div role="dialog" aria-modal="true" aria-label="Просмотр кадра"
      style={{ position: 'fixed', inset: 0, zIndex: 80, background: '#14100C', color: '#F0E6D2', display: 'flex', flexDirection: 'column', overscrollBehavior: 'contain' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '14px 20px' }}>
        <button style={btn} aria-label="Закрыть" onClick={onClose}>
          <svg {...ico}><path d="M6 6l12 12M18 6L6 18" /></svg>
        </button>
        <div style={{ font: '12px Inter, sans-serif', letterSpacing: '.16em', color: 'rgba(240,230,210,.6)' }}>
          КАДР {index + 1} ИЗ {Math.max(total, frames.length)}
        </div>
        <div style={{ flex: 1 }} />
        <span style={{ font: '13px Inter, sans-serif', color: 'rgba(240,230,210,.55)' }}>← → листать · Esc закрыть</span>
      </div>

      <div style={{ flex: 1, minHeight: 0, display: 'flex' }}>
        <div style={{ flex: 1, minWidth: 0, position: 'relative', padding: '0 12px' }}>
          <ZoomPan key={frame.id}>
            {(zoomed) => <RotatedPhoto src={frame.preview_url ?? frame.full_url} fullSrc={zoomed ? frame.full_url : null} rotation={rotation} />}
          </ZoomPan>
          {index > 0 && (
            <button style={{ ...btn, position: 'absolute', left: 20, top: '50%', marginTop: -22, width: 52, height: 52 }} aria-label="Предыдущий" onClick={prev}>
              <svg {...ico}><path d="M15 5l-7 7 7 7" /></svg>
            </button>
          )}
          {index < frames.length - 1 && (
            <button style={{ ...btn, position: 'absolute', right: 20, top: '50%', marginTop: -22, width: 52, height: 52 }} aria-label="Следующий" onClick={next}>
              <svg {...ico}><path d="M9 5l7 7-7 7" /></svg>
            </button>
          )}
        </div>

        <aside style={{ width: 340, flexShrink: 0, padding: '8px 28px 20px 12px', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 18 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
            <div style={{
              width: 44, height: 44, borderRadius: '50%', flexShrink: 0, border: '1px solid rgba(255,255,255,.3)',
              background: frame.guest_avatar_url ? `#2a1a10 center/cover no-repeat url(${frame.guest_avatar_url})` : 'rgba(255,179,71,.18)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: '#FFB347', font: '600 18px "Playfair Display", serif',
            }}>
              {!frame.guest_avatar_url && (frame.guest_name?.[0]?.toUpperCase() ?? '?')}
            </div>
            <div style={{ minWidth: 0 }}>
              <div style={{ font: '700 17px Manrope, Inter, sans-serif', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{frame.guest_name}</div>
              <div style={{ font: '13px Inter, sans-serif', color: 'rgba(240,230,210,.6)', marginTop: 2 }}>{fmtDate(frame.captured_at)}</div>
            </div>
          </div>
          {caption && <div style={{ font: '34px/1.15 Caveat, cursive', color: '#FFD9A0' }}>{caption}</div>}
          {frame.note && <p style={{ margin: 0, font: '15px/1.55 Manrope, Inter, sans-serif', color: 'rgba(240,230,210,.88)' }}>{frame.note}</p>}
          {(frame as Frame & { voice_url?: string | null }).voice_url && (
            <audio controls src={(frame as Frame & { voice_url?: string | null }).voice_url ?? undefined} style={{ width: '100%' }} />
          )}
          <div style={{ flex: 1 }} />
          <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
            <a style={action} href={frame.full_url} target="_blank" rel="noreferrer" download>
              <svg {...ico}><path d="M12 4v11M7 11l5 5 5-5M5 20h14" /></svg>Скачать оригинал
            </a>
            <button style={action} onClick={() => void share()}>
              <svg {...ico}><path d="M12 15V4M8 8l4-4 4 4M5 13v6h14v-6" /></svg>Поделиться
            </button>
            {onMore && (
              <button style={{ ...action, background: 'transparent', color: 'rgba(240,230,210,.7)' }} onClick={onMore}>
                Ещё: повернуть, пожаловаться…
              </button>
            )}
          </div>
          {note && <div style={{ font: '13px Inter, sans-serif', color: '#FFB347' }}>{note}</div>}
        </aside>
      </div>

      <div ref={stripRef} style={{ display: 'flex', gap: 6, padding: '10px 20px 16px', overflowX: 'auto', justifyContent: win.length * 70 < 900 ? 'center' : 'flex-start' }}>
        {win.map((f, k) => {
          const i = winStart + k
          const cur = i === index
          return (
            <button key={f.id} data-cur={cur ? '1' : undefined} onClick={() => onIndex(i)} aria-label={`Кадр ${i + 1}`}
              style={{
                flexShrink: 0, width: 64, height: 64, padding: 0, borderRadius: 6, overflow: 'hidden', cursor: 'pointer',
                border: cur ? '2px solid #FFB347' : '2px solid transparent', opacity: cur ? 1 : 0.55, background: '#2a1a10',
              }}>
              <img src={f.thumbnail_url ?? f.preview_url ?? f.full_url} alt="" loading="lazy" draggable={false}
                style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
            </button>
          )
        })}
      </div>
    </div>
  )
}
