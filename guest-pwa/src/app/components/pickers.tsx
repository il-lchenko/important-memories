import { useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { Icon, icons } from '../ui'

/* Выбор даты и времени в стиле календаря приложения (Material 3: бумажная поверхность, янтарный акцент). */

const MONTHS = ['январь', 'февраль', 'март', 'апрель', 'май', 'июнь', 'июль', 'август', 'сентябрь', 'октябрь', 'ноябрь', 'декабрь']
const MONTHS_GEN = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня', 'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря']
const MONTHS_SHORT = ['янв.', 'февр.', 'мар.', 'апр.', 'мая', 'июн.', 'июл.', 'авг.', 'сент.', 'окт.', 'нояб.', 'дек.']
const WEEK = ['П', 'В', 'С', 'Ч', 'П', 'С', 'В']
const WEEKDAYS_SHORT = ['вс', 'пн', 'вт', 'ср', 'чт', 'пт', 'сб']

const p2 = (n: number) => String(n).padStart(2, '0')
const sameDay = (a: Date, b: Date) => a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
const startOfDay = (d: Date) => new Date(d.getFullYear(), d.getMonth(), d.getDate())

/** Значение поля: 'YYYY-MM-DDTHH:mm' (дата и время) или 'YYYY-MM-DD' (только дата), локальное время устройства. */
export function parseLocal(v: string): Date | null {
  if (!v) return null
  const m = /^(\d{4})-(\d{2})-(\d{2})(?:T(\d{2}):(\d{2}))?/.exec(v)
  if (!m) return null
  return new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4] ?? 0), Number(m[5] ?? 0))
}
export function formatLocal(d: Date, withTime: boolean): string {
  const day = `${d.getFullYear()}-${p2(d.getMonth() + 1)}-${p2(d.getDate())}`
  return withTime ? `${day}T${p2(d.getHours())}:${p2(d.getMinutes())}` : day
}

function Dialog({ open, onClose, children }: { open: boolean; onClose: () => void; children: ReactNode }) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])
  if (!open) return null
  return (
    <div className="host-dialog-backdrop" onClick={onClose}>
      <div className="host-dialog" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>{children}</div>
    </div>
  )
}

function Actions({ onCancel, onOk, okDisabled }: { onCancel: () => void; onOk: () => void; okDisabled?: boolean }) {
  return (
    <div className="host-dialog-actions">
      <button className="host-text-btn" onClick={onCancel}>Отмена</button>
      <button className="host-text-btn" onClick={onOk} disabled={okDisabled}>ОК</button>
    </div>
  )
}

/* ── Календарь ── */

function CalendarDialog({ open, initial, min, max, onCancel, onPick }: {
  open: boolean; initial: Date; min?: Date; max?: Date; onCancel: () => void; onPick: (d: Date) => void
}) {
  const [sel, setSel] = useState(initial)
  const [view, setView] = useState(new Date(initial.getFullYear(), initial.getMonth(), 1))
  const [years, setYears] = useState(false)
  useEffect(() => {
    if (open) { setSel(initial); setView(new Date(initial.getFullYear(), initial.getMonth(), 1)); setYears(false) }
  }, [open, initial])

  const today = new Date()
  const minDay = min ? startOfDay(min) : null
  const maxDay = max ? startOfDay(max) : null
  const disabled = (d: Date) => (minDay !== null && d < minDay) || (maxDay !== null && d > maxDay)

  const cells = useMemo(() => {
    const first = new Date(view.getFullYear(), view.getMonth(), 1)
    const offset = (first.getDay() + 6) % 7
    const count = new Date(view.getFullYear(), view.getMonth() + 1, 0).getDate()
    return [...Array.from({ length: offset }, () => null), ...Array.from({ length: count }, (_, i) => new Date(view.getFullYear(), view.getMonth(), i + 1))]
  }, [view])

  const shift = (n: number) => setView(new Date(view.getFullYear(), view.getMonth() + n, 1))
  const canPrev = !minDay || new Date(view.getFullYear(), view.getMonth(), 0) >= minDay
  const canNext = !maxDay || new Date(view.getFullYear(), view.getMonth() + 1, 1) <= maxDay
  const y0 = (minDay ?? new Date(today.getFullYear() - 1, 0, 1)).getFullYear()
  const y1 = (maxDay ?? new Date(today.getFullYear() + 5, 0, 1)).getFullYear()
  const yearList = Array.from({ length: y1 - y0 + 1 }, (_, i) => y0 + i)

  return (
    <Dialog open={open} onClose={onCancel}>
      <div className="host-dialog-head">
        <div className="host-edge">Выберите дату</div>
        <div className="host-dialog-title">{WEEKDAYS_SHORT[sel.getDay()]}, {sel.getDate()} {MONTHS_SHORT[sel.getMonth()]}</div>
      </div>
      <div className="host-dialog-divider" />
      <div className="host-cal-nav">
        <button className="host-cal-month" onClick={() => setYears((v) => !v)} aria-expanded={years}>
          {MONTHS[view.getMonth()]} {view.getFullYear()}
          <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true" style={{ transform: years ? 'rotate(180deg)' : undefined }}><path d="M7 10l5 5 5-5z" fill="currentColor" /></svg>
        </button>
        {!years && (
          <div style={{ display: 'flex' }}>
            <button className="host-cal-arrow" aria-label="Предыдущий месяц" onClick={() => shift(-1)} disabled={!canPrev}><Icon d={icons.back} size={24} /></button>
            <button className="host-cal-arrow" aria-label="Следующий месяц" onClick={() => shift(1)} disabled={!canNext}><Icon d={icons.chevron} size={24} /></button>
          </div>
        )}
      </div>
      {years ? (
        <div className="host-cal-years">
          {yearList.map((y) => (
            <button key={y} data-on={y === view.getFullYear()} onClick={() => { setView(new Date(y, view.getMonth(), 1)); setYears(false) }}>{y}</button>
          ))}
        </div>
      ) : (
        <div className="host-cal-grid" role="grid">
          {WEEK.map((w, i) => <div key={i} className="host-cal-wd">{w}</div>)}
          {cells.map((d, i) => d === null ? <div key={`e${i}`} /> : (
            <button key={i} className="host-cal-day" disabled={disabled(d)}
              data-sel={sameDay(d, sel)} data-today={sameDay(d, today)}
              aria-label={`${d.getDate()} ${MONTHS_GEN[d.getMonth()]}`} onClick={() => setSel(d)}>
              {d.getDate()}
            </button>
          ))}
        </div>
      )}
      <Actions onCancel={onCancel} onOk={() => onPick(sel)} />
    </Dialog>
  )
}

/* ── Часы ── */

const C = 128
const R_OUT = 100
const R_IN = 66

function labelPos(index: number, radius: number) {
  const a = (index / 12) * Math.PI * 2
  return { x: C + radius * Math.sin(a), y: C - radius * Math.cos(a) }
}

function TimeDialog({ open, initial, onCancel, onPick }: {
  open: boolean; initial: { h: number; m: number }; onCancel: () => void; onPick: (h: number, m: number) => void
}) {
  const [h, setH] = useState(initial.h)
  const [m, setM] = useState(initial.m)
  const [mode, setMode] = useState<'h' | 'm'>('h')
  const svgRef = useRef<SVGSVGElement>(null)
  const dragging = useRef(false)
  useEffect(() => { if (open) { setH(initial.h); setM(initial.m); setMode('h') } }, [open, initial])

  const pointAt = (e: React.PointerEvent) => {
    const r = svgRef.current!.getBoundingClientRect()
    const k = 256 / r.width
    const dx = (e.clientX - r.left) * k - C
    const dy = (e.clientY - r.top) * k - C
    let ang = Math.atan2(dx, -dy)
    if (ang < 0) ang += Math.PI * 2
    return { ang, dist: Math.hypot(dx, dy) }
  }
  const apply = (e: React.PointerEvent) => {
    const { ang, dist } = pointAt(e)
    if (mode === 'h') {
      const idx = Math.round(ang / (Math.PI / 6)) % 12
      setH(dist < (R_OUT + R_IN) / 2 ? idx + 12 : idx)
    } else {
      setM(Math.round((ang / (Math.PI * 2)) * 60) % 60)
    }
  }
  const down = (e: React.PointerEvent) => { dragging.current = true; (e.currentTarget as Element).setPointerCapture(e.pointerId); apply(e) }
  const move = (e: React.PointerEvent) => { if (dragging.current) apply(e) }
  const up = () => { if (!dragging.current) return; dragging.current = false; if (mode === 'h') setMode('m') }

  const handPos = mode === 'h'
    ? labelPos(h % 12, h >= 12 ? R_IN : R_OUT)
    : (() => { const a = (m / 60) * Math.PI * 2; return { x: C + R_OUT * Math.sin(a), y: C - R_OUT * Math.cos(a) } })()

  return (
    <Dialog open={open} onClose={onCancel}>
      <div className="host-dialog-head">
        <div className="host-edge">Выберите время</div>
        <div className="host-time-head">
          <button data-on={mode === 'h'} onClick={() => setMode('h')} aria-label="Часы">{p2(h)}</button>
          <span>:</span>
          <button data-on={mode === 'm'} onClick={() => setMode('m')} aria-label="Минуты">{p2(m)}</button>
        </div>
      </div>
      <svg ref={svgRef} className="host-dial" viewBox="0 0 256 256" onPointerDown={down} onPointerMove={move} onPointerUp={up} onPointerCancel={up}>
        <circle cx={C} cy={C} r={C} fill="var(--paper-2)" />
        <line x1={C} y1={C} x2={handPos.x} y2={handPos.y} stroke="var(--amber)" strokeWidth="2" />
        <circle cx={C} cy={C} r="4" fill="var(--amber)" />
        <circle cx={handPos.x} cy={handPos.y} r="20" fill="var(--amber)" />
        {mode === 'm' && m % 5 !== 0 && <circle cx={handPos.x} cy={handPos.y} r="3" fill="#fff" />}
        {mode === 'h'
          ? Array.from({ length: 24 }, (_, v) => {
              const p = labelPos(v % 12, v >= 12 ? R_IN : R_OUT)
              const on = v === h
              return <text key={v} x={p.x} y={p.y} textAnchor="middle" dominantBaseline="central"
                fontSize={v >= 12 ? 14 : 16} fontFamily="Manrope, sans-serif" fontWeight={on ? 700 : 500} fill={on ? '#fff' : 'var(--ink)'} style={{ pointerEvents: 'none' }}>{p2(v)}</text>
            })
          : Array.from({ length: 12 }, (_, i) => {
              const p = labelPos(i, R_OUT)
              const on = m === i * 5
              return <text key={i} x={p.x} y={p.y} textAnchor="middle" dominantBaseline="central"
                fontSize="16" fontFamily="Manrope, sans-serif" fontWeight={on ? 700 : 500} fill={on ? '#fff' : 'var(--ink)'} style={{ pointerEvents: 'none' }}>{p2(i * 5)}</text>
            })}
      </svg>
      <Actions onCancel={onCancel} onOk={() => onPick(h, m)} />
    </Dialog>
  )
}

/* ── Поле ── */

function labelFor(d: Date, withTime: boolean): string {
  const date = `${d.getDate()} ${MONTHS_GEN[d.getMonth()]} ${d.getFullYear()}`
  return withTime ? `${date}, ${p2(d.getHours())}:${p2(d.getMinutes())}` : date
}

/** Поле даты (и времени) с календарём в стиле приложения. */
export function DateTimeField({ value, onChange, mode = 'datetime', min, max, placeholder = 'Выберите дату', ariaLabel, clearable }: {
  value: string; onChange: (v: string) => void; mode?: 'datetime' | 'date'; min?: Date; max?: Date; placeholder?: string; ariaLabel?: string; clearable?: boolean
}) {
  const withTime = mode === 'datetime'
  const current = parseLocal(value)
  const [step, setStep] = useState<'closed' | 'date' | 'time'>('closed')
  const [picked, setPicked] = useState<Date | null>(null)

  const fallback = useMemo(() => {
    const n = new Date()
    if (min && n < min) return min
    return n
  }, [min])
  const base = current ?? fallback

  const close = () => { setStep('closed'); setPicked(null) }
  return (
    <>
      <div style={{ position: 'relative' }}>
        <button type="button" className="host-date-field" data-empty={!current} aria-label={ariaLabel ?? placeholder} onClick={() => setStep('date')}
          style={clearable && current ? { paddingRight: 48 } : undefined}>
          <span style={{ flex: 1, textAlign: 'left' }}>{current ? labelFor(current, withTime) : placeholder}</span>
          <Icon d={icons.calendar} size={20} />
        </button>
        {clearable && current && (
          <button type="button" className="host-icon-btn" aria-label="Очистить" onClick={() => onChange('')}
            style={{ position: 'absolute', right: 40, top: 6, width: 40, height: 40, background: 'transparent' }}>
            <Icon d={icons.close} size={18} />
          </button>
        )}
      </div>
      <CalendarDialog open={step === 'date'} initial={base} min={min} max={max} onCancel={close}
        onPick={(d) => {
          if (!withTime) { onChange(formatLocal(d, false)); close(); return }
          setPicked(d); setStep('time')
        }} />
      <TimeDialog open={step === 'time'} initial={{ h: current ? current.getHours() : base.getHours(), m: current ? current.getMinutes() : base.getMinutes() }}
        onCancel={close}
        onPick={(h, m) => {
          const d = picked ?? base
          onChange(formatLocal(new Date(d.getFullYear(), d.getMonth(), d.getDate(), h, m), true))
          close()
        }} />
    </>
  )
}
