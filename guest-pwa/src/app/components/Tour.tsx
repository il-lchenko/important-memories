import { useCallback, useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { createPortal } from 'react-dom'
import { InstallGuide } from '../install'
import { Spark } from '../ui'
import '../tour.css'

/* Экскурсия по интерфейсу: затемнение, подсветка нужного элемента, короткая подсказка рядом. */

export interface TourStep {
  /** Значение атрибута data-tour у подсвечиваемого элемента. Без него шаг показывается по центру. */
  target?: string
  title: string
  text?: string
  /** Особый шаг: приветствие, готово или установка на телефон. */
  kind?: 'welcome' | 'finish' | 'install'
  /** Своё действие на последней кнопке (например, «Создать первый альбом»). */
  cta?: { label: string; run: () => void }
  extra?: ReactNode
}

interface Box { x: number; y: number; w: number; h: number; r: number }

const PAD = 7

function findVisible(name: string): HTMLElement | null {
  const all = Array.from(document.querySelectorAll<HTMLElement>(`[data-tour~="${name}"]`))
  return all.find((el) => { const b = el.getBoundingClientRect(); return b.width > 0 && b.height > 0 }) ?? null
}

function boxOf(el: HTMLElement): Box {
  const b = el.getBoundingClientRect()
  const cs = getComputedStyle(el)
  const raw = parseFloat(cs.borderTopLeftRadius) || 14
  const radius = cs.borderTopLeftRadius.includes('%') ? Math.min(b.width, b.height) / 2 + PAD : raw + PAD
  return { x: b.left - PAD, y: b.top - PAD, w: b.width + PAD * 2, h: b.height + PAD * 2, r: Math.min(radius, (Math.min(b.width, b.height) + PAD * 2) / 2) }
}

function Sparkle({ big }: { big: boolean }) {
  return (
    <div className="tour-sparkwrap" data-big={big} aria-hidden="true">
      <span className="tour-ring" /><span className="tour-ring" style={{ animationDelay: '1.1s' }} />
      <svg className="tour-spark" viewBox="0 0 24 24"><path d="M12 1Q14.4 9.6 23 12Q14.4 14.4 12 23Q9.6 14.4 1 12Q9.6 9.6 12 1Z" fill="var(--amber)" /></svg>
    </div>
  )
}

export function Tour({ steps: input, onClose }: { steps: TourStep[]; onClose: (completed: boolean) => void }) {
  const [steps] = useState(() => input.filter((s) => !s.target || findVisible(s.target)))
  const [i, setI] = useState(0)
  const [box, setBox] = useState<Box | null>(null)
  const [card, setCard] = useState({ w: 320, h: 220 })
  const [vp, setVp] = useState({ w: window.innerWidth, h: window.innerHeight })
  const cardRef = useRef<HTMLDivElement>(null)
  const step = steps[i]
  const last = i === steps.length - 1

  const measure = useCallback(() => {
    setVp({ w: window.innerWidth, h: window.innerHeight })
    const el = step?.target ? findVisible(step.target) : null
    setBox(el ? boxOf(el) : null)
  }, [step])

  useEffect(() => {
    if (steps.length === 0) onClose(false)
  }, [steps, onClose])

  useEffect(() => {
    const el = step?.target ? findVisible(step.target) : null
    if (el) {
      const b = el.getBoundingClientRect()
      const out = b.top < 90 || b.bottom > window.innerHeight - 150
      if (out) el.scrollIntoView({ block: 'center', behavior: 'smooth' })
    }
    measure()
    const t1 = window.setTimeout(measure, 120)
    const t2 = window.setTimeout(measure, 420)
    return () => { window.clearTimeout(t1); window.clearTimeout(t2) }
  }, [step, measure])

  useEffect(() => {
    let raf = 0
    const on = () => { cancelAnimationFrame(raf); raf = requestAnimationFrame(measure) }
    window.addEventListener('resize', on)
    window.addEventListener('scroll', on, true)
    return () => { cancelAnimationFrame(raf); window.removeEventListener('resize', on); window.removeEventListener('scroll', on, true) }
  }, [measure])

  useLayoutEffect(() => {
    const el = cardRef.current
    if (el) setCard({ w: el.offsetWidth, h: el.offsetHeight })
  }, [i, step])

  const finish = useCallback((ok: boolean) => onClose(ok), [onClose])
  const next = useCallback(() => { if (last) finish(true); else setI((n) => n + 1) }, [last, finish])

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') finish(false)
      else if (e.key === 'ArrowRight' || e.key === 'Enter') next()
      else if (e.key === 'ArrowLeft') setI((n) => Math.max(0, n - 1))
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [next, finish])

  if (!step) return null

  const cardW = Math.min(340, vp.w - 32)
  let top: number
  let left: number
  let arrow: { side: 'top' | 'bottom'; x: number } | null = null
  if (box) {
    const below = vp.h - (box.y + box.h)
    const placeBelow = below >= card.h + 28 || below >= box.y
    top = placeBelow ? box.y + box.h + 14 : box.y - 14 - card.h
    top = Math.max(16, Math.min(top, vp.h - card.h - 16))
    const cx = box.x + box.w / 2
    left = Math.max(16, Math.min(cx - cardW / 2, vp.w - cardW - 16))
    arrow = { side: placeBelow ? 'top' : 'bottom', x: Math.max(26, Math.min(cx - left, cardW - 26)) }
  } else {
    top = Math.max(16, (vp.h - card.h) / 2)
    left = (vp.w - cardW) / 2
  }

  const hole: React.CSSProperties = box
    ? { left: box.x, top: box.y, width: box.w, height: box.h, borderRadius: box.r, opacity: 1 }
    : { left: vp.w / 2, top: vp.h / 2, width: 0, height: 0, borderRadius: 0, opacity: 1 }
  const special = step.kind === 'welcome' || step.kind === 'finish'

  return createPortal(
    <div className="tour-root" role="dialog" aria-modal="true" aria-label="Подсказки"
      onWheel={(e) => e.preventDefault()} onTouchMove={(e) => e.preventDefault()}>
      <div className="tour-hole" data-ring={!!box} style={hole} />
      <div ref={cardRef} key={i} className="tour-card" style={{ top, left, width: cardW }}>
        {!last && <button className="tour-skip" onClick={() => finish(false)}>Пропустить</button>}
        {arrow && <span className="tour-arrow" data-side={arrow.side} style={{ left: arrow.x }} />}
        {special && <Sparkle big />}
        {!special && (
          <div className="tour-kicker">
            <Spark size={12} /> Шаг {i + 1} из {steps.length}
          </div>
        )}
        <h2 className="tour-title" data-special={special}>{step.title}</h2>
        {step.kind === 'install' ? <div style={{ margin: '4px 0 14px' }}><InstallGuide compact /></div>
          : step.text && <p className="tour-text" data-special={special}>{step.text}</p>}
        {step.extra}
        <div className="tour-actions">
          <div className="tour-dots" aria-hidden="true">
            {steps.map((_, k) => <span key={k} data-on={k === i} data-done={k < i} />)}
          </div>
          <div style={{ flex: 1 }} />
          {i > 0 && !special && <button className="tour-back" onClick={() => setI((n) => n - 1)} aria-label="Назад">←</button>}
          <button className="tour-next" onClick={() => { if (last && step.cta) { step.cta.run(); finish(true) } else next() }}>
            {last ? (step.cta?.label ?? 'Готово') : step.kind === 'welcome' ? 'Показать' : 'Далее'}
          </button>
        </div>
      </div>
    </div>,
    document.body,
  )
}

const keyOf = (name: string) => `im_tour_${name}_v1`
export function tourSeen(name: string): boolean {
  try { return localStorage.getItem(keyOf(name)) === '1' } catch { return true }
}
export function markTourSeen(name: string) {
  try { localStorage.setItem(keyOf(name), '1') } catch { /* без хранилища подсказки показываются при каждом входе */ }
}
export function resetTours() {
  try { ['albums', 'event'].forEach((n) => localStorage.removeItem(keyOf(n))) } catch { /* нечего сбрасывать */ }
}
