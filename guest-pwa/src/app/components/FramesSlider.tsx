const MIN = 6
const MAX = 30
const MAJORS = [6, 12, 18, 24, 30]
const THUMB = 7

function Sprockets() {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-evenly' }}>
      {Array.from({ length: 14 }, (_, i) => (
        <span key={i} style={{ width: 7, height: 5, borderRadius: 1.5, background: '#F0E8D4', border: '0.5px solid #C4A844' }} />
      ))}
    </div>
  )
}

/** Кадры на гостя: ползунок 6–30 с шагом в один кадр, как в приложении (плёночная лента, число, линейка). */
export function FramesSlider({ value, onChange, min = MIN, max = MAX }: {
  value: number; onChange: (n: number) => void; min?: number; max?: number
}) {
  const span = max - min
  const pct = ((value - min) / span) * 100
  const x = (v: number) => `calc(${THUMB}px + ${(v - min) / span} * (100% - ${THUMB * 2}px))`
  const active = MAJORS.filter((v) => v <= value).length
  return (
    <div>
      <div aria-hidden="true" style={{ position: 'relative', height: 56, background: '#DDD0B0', border: '1px solid #C4A844', borderRadius: 10, overflow: 'hidden', marginBottom: 16 }}>
        <div style={{ position: 'absolute', top: 5, left: 0, right: 0 }}><Sprockets /></div>
        <div style={{ position: 'absolute', bottom: 5, left: 0, right: 0 }}><Sprockets /></div>
        <div style={{ position: 'absolute', inset: '16px 10px', display: 'flex' }}>
          {MAJORS.map((_, i) => (
            <div key={i} style={{
              flex: 1, margin: '0 2px', borderRadius: 2, transition: 'background .12s',
              background: i < active ? 'rgba(196,168,68,.55)' : 'rgba(184,170,138,.2)',
            }} />
          ))}
        </div>
      </div>

      <div style={{ background: 'var(--paper-2)', borderRadius: 24, padding: '20px 16px 16px', textAlign: 'center' }}>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 56, fontWeight: 600, color: 'var(--amber)', lineHeight: 1.1, fontVariantNumeric: 'tabular-nums' }}>{value}</div>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 14, color: 'var(--ink-3)' }}>кадров на гостя</div>
        <input
          className="host-range" type="range" min={min} max={max} step={1} value={value}
          aria-label="Кадров на гостя" style={{ ['--pct' as string]: `${pct}%`, margin: '16px 0 2px' }}
          onChange={(e) => onChange(Number(e.target.value))}
        />
        <div aria-hidden="true" style={{ position: 'relative', height: 30 }}>
          {Array.from({ length: span + 1 }, (_, i) => min + i).map((v) => {
            const major = MAJORS.includes(v)
            const on = v <= value
            const sel = v === value
            return (
              <span key={v} style={{ position: 'absolute', left: x(v), top: 0, transform: 'translateX(-50%)', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
                <span style={{
                  width: major ? 1.5 : 1, height: major ? 9 : 4, borderRadius: 1,
                  background: major
                    ? (sel ? 'var(--amber)' : on ? 'rgba(201,136,30,.65)' : 'rgba(158,148,136,.55)')
                    : (on ? 'rgba(201,136,30,.45)' : 'rgba(158,148,136,.35)'),
                }} />
                {major && (
                  <span style={{ marginTop: 3, fontFamily: 'Inter, sans-serif', fontSize: 9, fontWeight: sel ? 700 : 400, color: sel ? 'var(--amber)' : on ? 'var(--ink-2, #4a4238)' : 'var(--ink-4)' }}>{v}</span>
                )}
              </span>
            )
          })}
        </div>
      </div>
    </div>
  )
}
