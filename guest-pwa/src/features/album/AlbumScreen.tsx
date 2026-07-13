import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, guestApi } from '../../api/client'
import { useNetworkStatus } from '../../hooks/useNetworkStatus'

export interface Frame {
  id: string
  guest_id: string
  guest_name: string
  guest_avatar_url?: string | null
  captured_at: string
  thumbnail_url: string | null
  preview_url: string | null
  full_url: string
  width: number
  height: number
  is_mine: boolean
  rotation?: number
  caption?: string | null
}

export interface AlbumOut {
  items: Frame[]
  next_cursor: string | null
  revealed: boolean
  total_frames: number
}

export type ViewMode = 'magazine' | 'retro' | 'polaroid'

function getEventMeta() {
  try { return JSON.parse(sessionStorage.getItem('event') ?? '{}') } catch { return {} }
}

function revealKicker(revealAt: string | null): string {
  if (!revealAt) return 'REVEALED'
  const d = new Date(revealAt)
  const time = d.toLocaleTimeString('ru', { hour: '2-digit', minute: '2-digit' })
  const day = String(d.getDate()).padStart(2, '0')
  const month = String(d.getMonth() + 1).padStart(2, '0')
  return `REVEALED ${time} · ${day}.${month}`
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('ru', { hour: '2-digit', minute: '2-digit' })
}

// Seeded PRNG so retro layout is stable per event
function mulberry32(seed: number) {
  return () => {
    let t = (seed = (seed + 0x6D2B79F5) | 0)
    t = Math.imul(t ^ (t >>> 15), t | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function hashStr(s: string): number {
  let h = 0
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0
  return h
}

// Film palette for placeholder gradients (matches host-app)
const FILM_GRADS: [string, string, string][] = [
  ['#F0C896', '#C97E4A', '#5A2A14'],
  ['#E8B888', '#B06A3A', '#3A1E10'],
  ['#D4955F', '#8C4A28', '#2A1810'],
  ['#F5D4A5', '#B8804A', '#4A2812'],
  ['#C98A5A', '#6E3A1A', '#1A0E08'],
  ['#E0A878', '#9A5A2A', '#3A1E10'],
]

// ── FrameImage ──────────────────────────────────────────────────────────────
// В сетках используем preview_url (2560px) → full_url. thumbnail_url (маленький)
// давал заметное падение качества на полароид/журнал/ретро — отказались.
function FrameImage({ frame, fallbackIndex }: { frame: Frame | null; fallbackIndex: number }) {
  const [previewFailed, setPreviewFailed] = useState(false)
  const rotation = frame?.rotation ?? 0
  const url = (previewFailed || !frame?.preview_url)
    ? (frame?.full_url ?? null)
    : frame.preview_url
  const grad = FILM_GRADS[fallbackIndex % FILM_GRADS.length]
  const rotStyle: React.CSSProperties = rotation
    ? { transform: `rotate(${rotation}deg)`, transformOrigin: 'center' }
    : {}
  if (url) {
    return (
      <img
        key={url}
        src={url}
        alt=""
        loading="lazy"
        style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', ...rotStyle }}
        onError={() => {
          if (!previewFailed && frame?.preview_url) setPreviewFailed(true)
        }}
      />
    )
  }
  return (
    <div style={{
      width: '100%', height: '100%',
      background: `radial-gradient(ellipse at ${fallbackIndex % 2 ? 30 : 65}% ${fallbackIndex % 3 ? 40 : 60}%, ${grad[0]}, ${grad[1]} 50%, ${grad[2]})`,
    }} />
  )
}

// ── ViewSwitcher ────────────────────────────────────────────────────────────
const MODES: { id: ViewMode; label: string }[] = [
  { id: 'magazine', label: 'Журнал' },
  { id: 'retro',    label: 'Ретро' },
  { id: 'polaroid', label: 'Полароид' },
]

export function ViewSwitcher({ mode, onChange }: { mode: ViewMode; onChange: (m: ViewMode) => void }) {
  return (
    <div style={{
      display: 'flex', padding: 4, gap: 4,
      background: 'var(--paper-2)', borderRadius: 14,
    }}>
      {MODES.map((m) => {
        const active = m.id === mode
        return (
          <button
            key={m.id}
            onClick={() => onChange(m.id)}
            style={{
              flex: 1, height: 36, borderRadius: 10,
              background: active ? 'var(--paper)' : 'transparent',
              border: 'none', cursor: 'pointer',
              fontFamily: 'Inter, sans-serif', fontSize: 12, fontWeight: 500,
              color: active ? 'var(--ink)' : 'var(--ink-3)',
              boxShadow: active ? '0 1px 2px rgba(0,0,0,.08)' : 'none',
              transition: 'background .18s, color .18s',
            }}
          >
            {m.label}
          </button>
        )
      })}
    </div>
  )
}

// ── GridFormatDialog ────────────────────────────────────────────────────────
export function GridFormatDialog({ current, onSelect, onClose }: {
  current: number; onSelect: (c: number) => void; onClose: () => void;
}) {
  const [selected, setSelected] = useState(current)

  return (
    <div
      onClick={onClose}
      style={{
        position: 'fixed', inset: 0, zIndex: 100,
        background: 'rgba(0,0,0,.35)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 20,
      }}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        style={{
          background: 'var(--paper)', borderRadius: 24,
          padding: '24px 22px', maxWidth: 360, width: '100%',
        }}
      >
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <h3 style={{ fontFamily: 'Fraunces, serif', fontWeight: 700, fontSize: 20, color: 'var(--ink)', margin: 0 }}>
            Формат журнала
          </h3>
          <button
            onClick={onClose}
            style={{ width: 32, height: 32, borderRadius: 9, background: 'var(--paper-2)', border: 'none', cursor: 'pointer', color: 'var(--ink-2)' }}
            aria-label="Закрыть"
          >×</button>
        </div>
        <p style={{ fontSize: 13, color: 'var(--ink-3)', margin: '6px 0 24px' }}>
          Сколько фото показывать в ряд
        </p>
        <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 10 }}>
          {[2, 3, 4].map((c) => {
            const active = selected === c
            return (
              <button
                key={c}
                onClick={() => setSelected(c)}
                style={{
                  padding: '14px 10px', borderRadius: 14,
                  background: active ? '#F5EDD8' : 'var(--paper-2)',
                  border: `2px solid ${active ? 'var(--amber)' : 'transparent'}`,
                  cursor: 'pointer',
                  display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12,
                  transition: 'background .15s, border-color .15s',
                }}
              >
                <div style={{ display: 'flex', gap: 3, width: '100%', height: c === 4 ? 26 : 34, alignItems: 'stretch' }}>
                  {Array.from({ length: c }).map((_, i) => (
                    <div key={i} style={{
                      flex: 1, borderRadius: 4,
                      background: `linear-gradient(135deg, ${FILM_GRADS[i % FILM_GRADS.length][0]}, ${FILM_GRADS[i % FILM_GRADS.length][2]})`,
                    }} />
                  ))}
                </div>
                <div style={{ fontFamily: 'Inter', fontSize: 13, fontWeight: 700, color: active ? 'var(--amber)' : 'var(--ink)' }}>
                  {c === 2 ? 'Крупный' : c === 3 ? 'Средний' : 'Мелкий'}
                </div>
                <div style={{ fontSize: 11, color: 'var(--ink-3)' }}>{c} в ряд</div>
              </button>
            )
          })}
        </div>
        <button
          className="btn-modal"
          onClick={() => { onSelect(selected); onClose() }}
          style={{ marginTop: 24 }}
        >
          Выбрать
        </button>
      </div>
    </div>
  )
}

// ── MagazineGrid (with 2/3/4 columns + pinch) ───────────────────────────────
export function MagazineGrid({ frames, columns, onOpenFrame, onColumnsChange }: {
  frames: Frame[]; columns: number; onOpenFrame: (i: number) => void;
  onColumnsChange: (c: number) => void;
}) {
  const pointers = useRef<Map<number, { x: number; y: number }>>(new Map())
  const pinchStart = useRef(0)
  const pinchHandled = useRef(false)

  const isLarge = columns === 2
  const isMedium = columns === 3
  const spacing = isLarge ? 6 : 4
  const radius = isLarge ? 8 : 6
  const aspect = isLarge ? '3 / 4' : (isMedium ? '2 / 3' : '1 / 1')

  return (
    <div
      onTouchStart={(e) => {
        for (const t of Array.from(e.touches)) pointers.current.set(t.identifier, { x: t.clientX, y: t.clientY })
        if (pointers.current.size === 2) {
          const ps = Array.from(pointers.current.values())
          pinchStart.current = Math.hypot(ps[0].x - ps[1].x, ps[0].y - ps[1].y)
          pinchHandled.current = false
        }
      }}
      onTouchMove={(e) => {
        for (const t of Array.from(e.touches)) pointers.current.set(t.identifier, { x: t.clientX, y: t.clientY })
        if (pinchHandled.current || pointers.current.size !== 2 || pinchStart.current < 10) return
        const ps = Array.from(pointers.current.values())
        const dist = Math.hypot(ps[0].x - ps[1].x, ps[0].y - ps[1].y)
        const scale = dist / pinchStart.current
        if (scale > 1.28 && columns > 2) {
          onColumnsChange(columns - 1)
          pinchHandled.current = true
        } else if (scale < 0.72 && columns < 4) {
          onColumnsChange(columns + 1)
          pinchHandled.current = true
        }
      }}
      onTouchEnd={(e) => {
        for (const t of Array.from(e.changedTouches)) pointers.current.delete(t.identifier)
      }}
      onTouchCancel={(e) => {
        for (const t of Array.from(e.changedTouches)) pointers.current.delete(t.identifier)
      }}
      style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${columns}, 1fr)`,
        gap: spacing,
        padding: '8px 16px 90px',
        touchAction: 'pan-y',
      }}
    >
      {frames.map((frame, i) => (
        <div
          key={frame.id}
          onClick={() => onOpenFrame(i)}
          style={{
            aspectRatio: aspect,
            background: '#2a1a10',
            position: 'relative', borderRadius: radius, overflow: 'hidden',
            cursor: 'pointer',
            boxShadow: isLarge ? '0 3px 8px rgba(26,23,20,.08)' : '0 2px 4px rgba(26,23,20,.04)',
            border: '0.5px solid var(--line)',
          }}
        >
          <FrameImage frame={frame} fallbackIndex={i} />
          {isLarge && (
            <>
              <div style={{
                position: 'absolute', top: 8, right: 10,
                padding: '2px 5px', borderRadius: 4,
                background: 'rgba(0,0,0,.3)',
                fontFamily: 'JetBrains Mono, monospace', fontSize: 9,
                color: 'rgba(255,210,170,.85)',
              }}>
                {formatTime(frame.captured_at)}
              </div>
              <div style={{
                position: 'absolute', bottom: 8, left: 10, right: 10,
                fontFamily: 'Caveat, cursive',
                fontStyle: (frame.caption ?? '').trim() ? 'italic' : 'normal',
                fontSize: (frame.caption ?? '').trim() ? 18 : 19,
                color: '#fff', lineHeight: 1.15,
                textShadow: '0 1px 4px rgba(0,0,0,.65)',
                display: '-webkit-box', WebkitBoxOrient: 'vertical' as const,
                WebkitLineClamp: 3, overflow: 'hidden',
              }}>
                {(frame.caption ?? '').trim() || frame.guest_name}
              </div>
            </>
          )}
        </div>
      ))}
    </div>
  )
}

// ── RetroLayout ─────────────────────────────────────────────────────────────
export function RetroLayout({ frames, eventId, onOpenFrame }: {
  frames: Frame[]; eventId: string; onOpenFrame: (i: number) => void;
}) {
  const rows = useMemo(() => {
    const seed = hashStr(eventId) ^ (frames.length * 97)
    const rnd = mulberry32(seed)
    const result: { single?: number; pair?: [number, number]; gap: number; layout: number[] }[] = []
    let i = 0
    while (i < frames.length) {
      if (result.length > 0) {
        result[result.length - 1].gap = Math.floor(rnd() * 12) + 6
      }
      const remaining = frames.length - i
      if (remaining >= 2 && Math.floor(rnd() * 5) > 1) {
        result.push({ pair: [i, i + 1], gap: 0, layout: [rnd(), rnd(), rnd(), rnd(), rnd(), rnd(), rnd(), rnd(), rnd(), rnd(), rnd(), rnd()] })
        i += 2
      } else {
        result.push({ single: i, gap: 0, layout: [rnd(), rnd(), rnd(), rnd(), rnd()] })
        i++
      }
    }
    return result
  }, [frames.length, eventId])

  return (
    <div style={{ padding: '16px 20px 90px', overflow: 'hidden' }}>
      {rows.map((row, idx) => (
        <div key={idx} style={{ marginTop: idx === 0 ? 0 : row.gap }}>
          {row.single !== undefined ? (
            <RetroSingleRow
              frameIndex={row.single}
              frame={frames[row.single]}
              layout={row.layout}
              onOpen={onOpenFrame}
            />
          ) : row.pair ? (
            <RetroDoubleRow
              indices={row.pair}
              frames={frames}
              layout={row.layout}
              onOpen={onOpenFrame}
            />
          ) : null}
        </div>
      ))}
    </div>
  )
}

function RetroSingleRow({ frameIndex, frame, layout, onOpen }: {
  frameIndex: number; frame: Frame; layout: number[]; onOpen: (i: number) => void;
}) {
  const sizes = [[300, 215], [250, 305], [275, 205], [230, 280]]
  const chosen = sizes[Math.floor(layout[0] * sizes.length)]
  const containerW = Math.min(window.innerWidth - 40, 360)
  const s = Math.min(1, containerW / 350)
  const w = chosen[0] * s
  const h = chosen[1] * s
  const deg = layout[1] * 28 - 14
  const alignIdx = Math.floor(layout[2] * 3)
  const justifyMap = ['flex-start', 'center', 'flex-end'] as const
  const xPad = (layout[3] * 18 + 4) * s
  const tape = retroTape(layout[4])
  return (
    <div style={{ display: 'flex', justifyContent: justifyMap[alignIdx] }}>
      <div style={{
        paddingLeft: alignIdx === 0 ? xPad : 0,
        paddingRight: alignIdx === 2 ? xPad : 0,
      }}>
        <RetroCard
          w={w} h={h} deg={deg} index={frameIndex} frame={frame}
          tape={tape} hw={((frame.caption ?? '').trim() || null)}
          onTap={() => onOpen(frameIndex)}
        />
      </div>
    </div>
  )
}

function RetroDoubleRow({ indices, frames, layout, onOpen }: {
  indices: [number, number]; frames: Frame[]; layout: number[]; onOpen: (i: number) => void;
}) {
  const containerW = Math.min(window.innerWidth - 40, 360)
  const s = Math.min(1, containerW / 350)
  const wL = (layout[0] * 55 + 145) * s
  const hL = (layout[1] * 70 + 160) * s
  const degL = layout[2] * 28 - 14
  const wR = (layout[3] * 55 + 135) * s
  const hR = (layout[4] * 70 + 150) * s
  const degR = layout[5] * 28 - 14
  const topOffset = layout[6] * 44 * s
  const leftFirst = layout[7] > 0.5
  const leftPad = (layout[8] * 10 + 2) * s
  const gap = (layout[9] * 8 + 3) * s
  const tapeL = retroTape(layout[10])
  const tapeR = retroTape(layout[11])

  const [iL, iR] = indices
  const fL = frames[iL]
  const fR = frames[iR]

  const cardL = (
    <RetroCard
      w={wL} h={hL} deg={degL} index={iL} frame={fL}
      tape={tapeL} hw={((fL.caption ?? '').trim() || null)}
      onTap={() => onOpen(iL)}
    />
  )
  const cardR = (
    <div style={{ marginTop: topOffset }}>
      <RetroCard
        w={wR} h={hR} deg={degR} index={iR} frame={fR}
        tape={tapeR} hw={((fR.caption ?? '').trim() || null)}
        onTap={() => onOpen(iR)}
      />
    </div>
  )

  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', overflow: 'visible' }}>
      <div style={{ width: leftPad, flexShrink: 0 }} />
      {leftFirst ? cardL : cardR}
      <div style={{ width: gap, flexShrink: 0 }} />
      {leftFirst ? cardR : cardL}
    </div>
  )
}

function retroTape(r: number): string | null {
  const v = Math.floor(r * 6)
  if (v === 2) return 'var(--amber)'
  if (v === 3) return '#D54B3D'
  if (v === 4) return '#F6F2E8'
  return null
}

function RetroCard({ w, h, deg, index, frame, tape, hw, onTap }: {
  w: number; h: number; deg: number; index: number;
  frame: Frame | null; tape: string | null; hw: string | null;
  onTap?: () => void;
}) {
  return (
    <div
      onClick={onTap}
      style={{
        transform: `rotate(${deg}deg)`,
        width: w, height: h, position: 'relative',
        cursor: 'pointer',
        boxShadow: '0 4px 10px rgba(26,23,20,.18), 0 1px 2px rgba(26,23,20,.08)',
      }}
    >
      <div style={{ width: '100%', height: '100%', overflow: 'hidden' }}>
        <FrameImage frame={frame} fallbackIndex={index} />
      </div>
      {hw && (
        <div style={{
          position: 'absolute', bottom: 6, left: 10, right: 10,
          transform: 'rotate(-2deg)',
          fontFamily: 'Caveat, cursive', fontStyle: 'italic',
          fontSize: 16, color: '#fff', lineHeight: 1.15,
          textShadow: '0 1px 4px rgba(0,0,0,.65)',
          display: '-webkit-box', WebkitBoxOrient: 'vertical' as const,
          WebkitLineClamp: 3, overflow: 'hidden',
          textAlign: 'right',
        }}>
          {hw}
        </div>
      )}
      {tape && (
        <div style={{
          position: 'absolute', top: -9, left: w * 0.2,
          width: 56, height: 18,
          background: tape, opacity: 0.58,
          transform: 'rotate(-3deg)',
          boxShadow: '0 1px 2px rgba(26,23,20,.1)',
        }} />
      )}
    </div>
  )
}

// ── PolaroidCaption ─────────────────────────────────────────────────────────
// Универсальная белая зона внизу полароида: показывает только caption (растёт
// по длине). Если caption нет — рисуем компактную пустую полоску (классический
// полароид). Имя гостя здесь не пишем — оно живёт в мета-полосе полноэкрана.
// Используется в PolaroidFeed, MagazineGrid (крупная сетка), CameraScreen preview,
// CaptionScreen, FrameFullscreen.
export function PolaroidCaption({ caption, capturedAt, compact = false }: {
  caption?: string | null; guestName?: string | null;
  capturedAt?: string | null; compact?: boolean;
}) {
  const trimmed = (caption ?? '').trim()
  const hasCaption = trimmed.length > 0
  const time = capturedAt ? formatTime(capturedAt) : null
  const scale = compact ? 0.72 : 1
  return (
    <div style={{
      padding: `${8 * scale}px ${14 * scale}px ${10 * scale}px`,
      position: 'relative',
      display: 'flex', flexDirection: 'column', justifyContent: 'center',
    }}>
      {hasCaption ? (
        <div style={{
          fontFamily: 'Caveat, cursive', fontStyle: 'italic',
          fontSize: (compact ? 17 : 22),
          lineHeight: 1.22,
          color: 'var(--ink-2)',
          textAlign: 'center',
          wordBreak: 'break-word', overflowWrap: 'anywhere',
          padding: '0 4px',
        }}>
          {trimmed}
        </div>
      ) : (
        <div style={{ height: 12 * scale }} />
      )}
      {time && (
        <div style={{
          fontFamily: 'JetBrains Mono, monospace',
          fontSize: (compact ? 8 : 10), color: 'var(--ink-3)',
          textAlign: 'right', marginTop: 4, letterSpacing: '.06em',
        }}>
          {time}
        </div>
      )}
    </div>
  )
}

// ── PolaroidFeed ────────────────────────────────────────────────────────────
const POLAROID_ROTS = [-3.5, 3.0, -2.0, 4.0, -2.8, 2.5]

export function PolaroidFeed({ frames, onOpenFrame }: {
  frames: Frame[]; onOpenFrame: (i: number) => void;
}) {
  return (
    <div style={{ padding: '16px 20px 90px', overflow: 'hidden' }}>
      {frames.map((frame, i) => {
        const deg = POLAROID_ROTS[i % POLAROID_ROTS.length]
        return (
          <div key={frame.id} style={{ display: 'flex', justifyContent: 'center', marginTop: i === 0 ? 0 : 20 }}>
            <div
              onClick={() => onOpenFrame(i)}
              style={{
                width: 280,
                background: 'var(--paper)',
                borderRadius: 4,
                transform: `rotate(${deg}deg)`,
                boxShadow: '0 12px 26px -6px rgba(26,23,20,.22), 0 2px 4px rgba(26,23,20,.08)',
                cursor: 'pointer',
              }}
            >
              <div style={{ padding: '14px 14px 0' }}>
                <div style={{ aspectRatio: '1 / 1', overflow: 'hidden', borderRadius: 2 }}>
                  <FrameImage frame={frame} fallbackIndex={i} />
                </div>
              </div>
              <PolaroidCaption caption={frame.caption} guestName={frame.guest_name} capturedAt={frame.captured_at} />
            </div>
          </div>
        )
      })}
    </div>
  )
}

// ── Main AlbumScreen ────────────────────────────────────────────────────────
export default function AlbumScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const online = useNetworkStatus()

  const [frames, setFrames] = useState<Frame[]>([])
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [nextCursor, setNextCursor] = useState<string | null>(null)
  const [totalFrames, setTotalFrames] = useState<number>(0)
  const [mode, setMode] = useState<ViewMode>('magazine')
  const [columns, setColumns] = useState<number>(2)
  const [showGridDialog, setShowGridDialog] = useState(false)
  const sentinelRef = useRef<HTMLDivElement>(null)

  const event = getEventMeta()
  const eventId: string = event.id ?? ''
  const eventName: string = event.title ?? 'Альбом'
  const kicker = revealKicker(event.settings?.reveal_at ?? null)

  const authorCount = useMemo(
    () => new Set(frames.map((f) => f.guest_id)).size,
    [frames],
  )

  const getEventId = async (): Promise<string | null> => {
    if (event.id) return event.id
    try {
      const { data } = await guestApi.getSession()
      sessionStorage.setItem('event', JSON.stringify(data.event))
      return data.event.id
    } catch { return null }
  }

  const fetchPage = async (cursor: string | null = null, eid?: string): Promise<boolean> => {
    const id = eid ?? event.id
    if (!id) return false
    const params: Record<string, string> = {}
    if (cursor) params.cursor = cursor
    const { data } = await api.get<AlbumOut>(`/events/${id}/album`, { params })
    if (!data.revealed) return false
    setFrames((prev) => (cursor ? [...prev, ...data.items] : data.items))
    setNextCursor(data.next_cursor)
    setTotalFrames(data.total_frames)
    return true
  }

  // Initial load
  useEffect(() => {
    const revealAtStr = event.settings?.reveal_at
    if (revealAtStr && new Date(revealAtStr) > new Date()) {
      navigate(`/g/${shortCode}/waiting`, { replace: true })
      return
    }
    getEventId().then((eid) => {
      if (!eid) { setLoading(false); return }
      fetchPage(null, eid)
        .then((revealed) => {
          if (!revealed) navigate(`/g/${shortCode}/waiting`, { replace: true })
        })
        .catch((e) => console.error('album_load_failed', e))
        .finally(() => setLoading(false))
    })
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  // Infinite scroll
  useEffect(() => {
    if (!sentinelRef.current || !nextCursor) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && nextCursor && !loadingMore) {
          setLoadingMore(true)
          fetchPage(nextCursor)
            .catch((e) => console.error('album_page_failed', e))
            .finally(() => setLoadingMore(false))
        }
      },
      { rootMargin: '200px' },
    )
    observer.observe(sentinelRef.current)
    return () => observer.disconnect()
  }, [nextCursor, loadingMore]) // eslint-disable-line react-hooks/exhaustive-deps

  const openFrame = (index: number) => {
    navigate(`/g/${shortCode}/f/${index}`, {
      state: { frames, totalFrames },
    })
  }

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)' }}>
      {/* Offline banner */}
      {!online && (
        <div style={{
          position: 'sticky', top: 0, zIndex: 10,
          background: 'var(--ink)', color: 'var(--dr-text)',
          padding: '10px 16px',
          display: 'flex', alignItems: 'center', gap: 8,
          fontFamily: 'Inter, sans-serif', fontSize: 13,
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="1" y1="1" x2="23" y2="23" />
            <path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55M5 12.55a10.94 10.94 0 0 1 5.17-2.39M10.71 5.05A16 16 0 0 1 22.56 9M1.42 9a15.91 15.91 0 0 1 4.7-2.88M8.53 16.11a6 6 0 0 1 6.95 0" />
            <circle cx="12" cy="20" r="1" fill="currentColor" stroke="none" />
          </svg>
          Нет подключения — показаны кэшированные фото
        </div>
      )}

      {/* Header */}
      <div style={{ padding: '14px 24px 8px', display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontFamily: 'JetBrains Mono, monospace', fontSize: 11,
            letterSpacing: '.14em', textTransform: 'uppercase',
            color: 'var(--ink-3)', marginBottom: 6,
          }}>
            {kicker}
          </div>
          <h1 style={{
            fontFamily: 'Fraunces, serif', fontStyle: 'italic',
            fontSize: 26, fontWeight: 500, margin: 0,
            letterSpacing: '-.02em', lineHeight: 1.05, color: 'var(--ink)',
          }}>
            {eventName}
          </h1>
          <div style={{
            fontFamily: 'JetBrains Mono, monospace', fontSize: 11,
            letterSpacing: '.14em', color: 'var(--ink-3)',
            textTransform: 'uppercase', marginTop: 4,
          }}>
            {loading
              ? '...'
              : `${totalFrames} КАДРОВ · ${authorCount} АВТОРОВ`}
          </div>
        </div>
        <button
          onClick={() => navigate(`/g/${shortCode}/profile`)}
          aria-label="Профиль"
          style={{
            width: 40, height: 40, borderRadius: 20,
            background: 'var(--paper-2)', border: 'none', cursor: 'pointer',
            color: 'var(--ink-2)', flexShrink: 0,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}
        >
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="8" r="4" />
            <path d="M4 21c1.5-4 4.5-6 8-6s6.5 2 8 6" />
          </svg>
        </button>
      </div>

      {/* Mode switcher + grid format trigger */}
      <div style={{ padding: '10px 16px 6px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{ flex: 1 }}>
          <ViewSwitcher mode={mode} onChange={setMode} />
        </div>
        {mode === 'magazine' && (
          <button
            onClick={() => setShowGridDialog(true)}
            aria-label="Формат сетки"
            style={{
              width: 44, height: 44, borderRadius: 12,
              background: 'var(--paper-2)', border: 'none', cursor: 'pointer',
              color: 'var(--ink)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
            }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/>
              <rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>
            </svg>
          </button>
        )}
      </div>

      {/* Body */}
      {loading ? (
        <div style={{ display: 'flex', justifyContent: 'center', padding: 48 }}>
          <span style={{ color: 'var(--ink-3)', fontFamily: 'JetBrains Mono, monospace', fontSize: 13 }}>
            Загрузка...
          </span>
        </div>
      ) : frames.length === 0 ? (
        <div style={{
          display: 'flex', flexDirection: 'column',
          alignItems: 'center', justifyContent: 'center',
          padding: '64px 24px', textAlign: 'center',
        }}>
          <div style={{ marginBottom: 16, opacity: 0.3 }}>
            <svg width="48" height="48" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 7h4l2-3h6l2 3h4v13H3z" /><circle cx="12" cy="13" r="4" />
            </svg>
          </div>
          <p style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontSize: 18, color: 'var(--ink-3)', margin: 0 }}>
            Кадров пока нет
          </p>
        </div>
      ) : (
        <>
          {mode === 'magazine' && (
            <MagazineGrid
              frames={frames}
              columns={columns}
              onOpenFrame={openFrame}
              onColumnsChange={setColumns}
            />
          )}
          {mode === 'retro' && (
            <RetroLayout frames={frames} eventId={eventId} onOpenFrame={openFrame} />
          )}
          {mode === 'polaroid' && (
            <PolaroidFeed frames={frames} onOpenFrame={openFrame} />
          )}

          {/* Sentinel for infinite scroll */}
          <div ref={sentinelRef} style={{ height: 1 }} />

          {loadingMore && (
            <div style={{ display: 'flex', justifyContent: 'center', padding: '24px 0' }}>
              <span style={{ color: 'var(--ink-3)', fontFamily: 'JetBrains Mono, monospace', fontSize: 12 }}>
                Загрузка...
              </span>
            </div>
          )}
        </>
      )}

      {showGridDialog && (
        <GridFormatDialog
          current={columns}
          onSelect={setColumns}
          onClose={() => setShowGridDialog(false)}
        />
      )}
    </div>
  )
}
