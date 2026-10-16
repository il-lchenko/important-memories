import { useEffect, useRef, useState, type ReactNode } from 'react'

const MAX_SCALE = 8
const DOUBLE_TAP_SCALE = 3

interface View { s: number; x: number; y: number }

/**
 * Масштабирование и перемещение содержимого: щипок двумя пальцами, двойное касание,
 * колесо мыши, перетаскивание, кнопки «+/−» на устройствах с мышью.
 * Пока масштаб больше единицы, касания не доходят до родителя, поэтому свайп
 * «следующее фото» не срабатывает при перемещении по увеличенному кадру.
 */
export function ZoomPan({ children }: { children: (zoomed: boolean) => ReactNode }) {
  const ref = useRef<HTMLDivElement>(null)
  const [view, setView] = useState<View>({ s: 1, x: 0, y: 0 })
  const viewRef = useRef(view)
  viewRef.current = view
  const [hasMouse, setHasMouse] = useState(false)

  const multi = useRef(false)
  const pinch = useRef<{ d: number; s: number; mx: number; my: number; x: number; y: number } | null>(null)
  const drag = useRef<{ px: number; py: number; x: number; y: number; moved: boolean } | null>(null)
  const lastTap = useRef<{ t: number; x: number; y: number } | null>(null)

  useEffect(() => {
    try { setHasMouse(window.matchMedia('(hover: hover) and (pointer: fine)').matches) } catch { /* ignore */ }
  }, [])

  const apply = (s: number, x: number, y: number) => {
    const el = ref.current
    const ns = Math.min(MAX_SCALE, Math.max(1, s))
    if (!el || ns <= 1.001) { setView({ s: 1, x: 0, y: 0 }); return }
    const r = el.getBoundingClientRect()
    const maxX = (r.width * (ns - 1)) / 2
    const maxY = (r.height * (ns - 1)) / 2
    setView({ s: ns, x: Math.min(maxX, Math.max(-maxX, x)), y: Math.min(maxY, Math.max(-maxY, y)) })
  }

  /** Точка (в координатах экрана) остаётся на месте при смене масштаба. */
  const zoomAt = (clientX: number, clientY: number, ns: number) => {
    const el = ref.current
    if (!el) return
    const r = el.getBoundingClientRect()
    const cx = clientX - (r.left + r.width / 2)
    const cy = clientY - (r.top + r.height / 2)
    const v = viewRef.current
    const k = ns / v.s
    apply(ns, cx - (cx - v.x) * k, cy - (cy - v.y) * k)
  }

  const toggleZoom = (clientX: number, clientY: number) => {
    if (viewRef.current.s > 1.05) apply(1, 0, 0)
    else zoomAt(clientX, clientY, DOUBLE_TAP_SCALE)
  }

  const dist = (t: React.TouchList) => Math.hypot(t[0].clientX - t[1].clientX, t[0].clientY - t[1].clientY)
  const mid = (t: React.TouchList) => ({ x: (t[0].clientX + t[1].clientX) / 2, y: (t[0].clientY + t[1].clientY) / 2 })

  const onTouchStart = (e: React.TouchEvent) => {
    if (e.touches.length >= 2) {
      multi.current = true
      const el = ref.current
      if (!el) return
      const r = el.getBoundingClientRect()
      const m = mid(e.touches)
      const v = viewRef.current
      pinch.current = { d: dist(e.touches), s: v.s, mx: m.x - (r.left + r.width / 2), my: m.y - (r.top + r.height / 2), x: v.x, y: v.y }
      drag.current = null
      e.stopPropagation()
      return
    }
    const t = e.touches[0]
    drag.current = { px: t.clientX, py: t.clientY, x: viewRef.current.x, y: viewRef.current.y, moved: false }
    if (viewRef.current.s > 1.001) e.stopPropagation()
  }

  const onTouchMove = (e: React.TouchEvent) => {
    const el = ref.current
    if (!el) return
    if (pinch.current && e.touches.length >= 2) {
      const r = el.getBoundingClientRect()
      const m = mid(e.touches)
      const p = pinch.current
      const ns = Math.min(MAX_SCALE, Math.max(1, (p.s * dist(e.touches)) / p.d))
      const cx = m.x - (r.left + r.width / 2)
      const cy = m.y - (r.top + r.height / 2)
      const k = ns / p.s
      apply(ns, cx - (p.mx - p.x) * k, cy - (p.my - p.y) * k)
      e.stopPropagation()
      return
    }
    const d = drag.current
    if (d && e.touches.length === 1 && viewRef.current.s > 1.001) {
      const t = e.touches[0]
      const dx = t.clientX - d.px
      const dy = t.clientY - d.py
      if (Math.abs(dx) + Math.abs(dy) > 4) d.moved = true
      apply(viewRef.current.s, d.x + dx, d.y + dy)
      e.stopPropagation()
    }
  }

  const onTouchEnd = (e: React.TouchEvent) => {
    const wasMulti = multi.current
    const zoomed = viewRef.current.s > 1.001
    if (e.touches.length === 0) {
      multi.current = false
      pinch.current = null
      const d = drag.current
      drag.current = null
      if (!wasMulti && d && !d.moved) {
        const t = e.changedTouches[0]
        const now = Date.now()
        const prev = lastTap.current
        if (prev && now - prev.t < 300 && Math.hypot(prev.x - t.clientX, prev.y - t.clientY) < 30) {
          lastTap.current = null
          toggleZoom(t.clientX, t.clientY)
        } else {
          lastTap.current = { t: now, x: t.clientX, y: t.clientY }
        }
      }
    } else if (e.touches.length === 1 && wasMulti) {
      const t = e.touches[0]
      drag.current = { px: t.clientX, py: t.clientY, x: viewRef.current.x, y: viewRef.current.y, moved: true }
      pinch.current = null
    }
    if (wasMulti || zoomed) e.stopPropagation()
  }

  const onWheel = (e: React.WheelEvent) => {
    const f = Math.exp(-e.deltaY * (e.ctrlKey ? 0.01 : 0.0018))
    zoomAt(e.clientX, e.clientY, viewRef.current.s * f)
  }

  const onMouseDown = (e: React.MouseEvent) => {
    if (viewRef.current.s <= 1.001 || e.button !== 0) return
    drag.current = { px: e.clientX, py: e.clientY, x: viewRef.current.x, y: viewRef.current.y, moved: false }
    e.preventDefault()
  }
  const onMouseMove = (e: React.MouseEvent) => {
    const d = drag.current
    if (!d || e.buttons !== 1) return
    apply(viewRef.current.s, d.x + e.clientX - d.px, d.y + e.clientY - d.py)
  }
  const onMouseUp = () => { drag.current = null }

  const zoomed = view.s > 1.001
  const btn = {
    width: 40, height: 40, borderRadius: 2, border: '1px solid rgba(240,230,210,.5)',
    background: 'rgba(22,16,12,.7)', color: '#F0E6D2', cursor: 'pointer', fontSize: 20, lineHeight: 1,
    fontFamily: 'Inter, sans-serif',
  } as const

  return (
    <div
      ref={ref}
      style={{ position: 'absolute', inset: 0, overflow: 'hidden', touchAction: 'none', cursor: zoomed ? 'grab' : 'zoom-in' }}
      onTouchStart={onTouchStart}
      onTouchMove={onTouchMove}
      onTouchEnd={onTouchEnd}
      onWheel={onWheel}
      onMouseDown={onMouseDown}
      onMouseMove={onMouseMove}
      onMouseUp={onMouseUp}
      onMouseLeave={onMouseUp}
      onDoubleClick={(e) => { if (hasMouse) toggleZoom(e.clientX, e.clientY) }}
    >
      <div
        style={{
          position: 'absolute', inset: 0,
          transform: `translate(${view.x}px, ${view.y}px) scale(${view.s})`,
          transformOrigin: 'center center',
          willChange: 'transform',
        }}
      >
        {children(zoomed)}
      </div>

      {hasMouse && (
        <div style={{ position: 'absolute', right: 12, bottom: 12, display: 'flex', gap: 6, zIndex: 3 }}
          onDoubleClick={(e) => e.stopPropagation()} onMouseDown={(e) => e.stopPropagation()}>
          <button style={btn} aria-label="Уменьшить" onClick={() => zoomAt(window.innerWidth / 2, window.innerHeight / 2, viewRef.current.s / 1.6)}>−</button>
          <button style={btn} aria-label="Увеличить" onClick={() => zoomAt(window.innerWidth / 2, window.innerHeight / 2, viewRef.current.s * 1.6)}>+</button>
          {zoomed && <button style={{ ...btn, fontSize: 13, width: 'auto', padding: '0 10px' }} aria-label="Сбросить масштаб" onClick={() => apply(1, 0, 0)}>Сброс</button>}
        </div>
      )}
    </div>
  )
}
