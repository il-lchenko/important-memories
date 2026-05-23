import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api, guestApi } from '../../api/client'
import { useNetworkStatus } from '../../hooks/useNetworkStatus'

interface Frame {
  id: string
  guest_id: string
  guest_name: string
  captured_at: string
  thumbnail_url: string | null
  full_url: string
  width: number
  height: number
  is_mine: boolean
}

interface AlbumOut {
  items: Frame[]
  next_cursor: string | null
  revealed: boolean
  total_frames: number
}

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

export default function AlbumScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const online = useNetworkStatus()

  const [frames, setFrames] = useState<Frame[]>([])
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [nextCursor, setNextCursor] = useState<string | null>(null)
  const [totalFrames, setTotalFrames] = useState<number>(0)
  const sentinelRef = useRef<HTMLDivElement>(null)

  const event = getEventMeta()
  const eventName: string = event.title ?? 'Альбом'
  const kicker = revealKicker(event.settings?.reveal_at ?? null)
  const photoFormat: string = event.settings?.photo_format ?? 'portrait_34'

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

  const fetchPage = async (cursor: string | null = null, eventId?: string): Promise<boolean> => {
    const eid = eventId ?? event.id
    if (!eid) return false
    const params: Record<string, string> = {}
    if (cursor) params.cursor = cursor
    const { data } = await api.get<AlbumOut>(`/events/${eid}/album`, { params })
    if (!data.revealed) return false
    setFrames((prev) => {
      const next = cursor ? [...prev, ...data.items] : data.items
      return next
    })
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
        .catch(() => {})
        .finally(() => setLoading(false))
    })
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  // Infinite scroll via IntersectionObserver
  useEffect(() => {
    if (!sentinelRef.current || !nextCursor) return
    const observer = new IntersectionObserver(
      (entries) => {
        if (entries[0].isIntersecting && nextCursor && !loadingMore) {
          setLoadingMore(true)
          fetchPage(nextCursor)
            .catch(() => {})
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
      <div style={{ padding: '14px 24px 8px' }}>
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

      {/* Grid */}
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
          <div style={{
            display: 'grid',
            gridTemplateColumns: '1fr 1fr',
            gap: 8, padding: '8px 16px 30px',
          }}>
            {frames.map((frame, index) => {
              // Landscape 4:3 layout: PP / L / PP / L ...
              // index % 3 === 2 → full-width landscape tile
              const isLandscapeEvent = photoFormat === 'landscape_43'
              const isFullWidth = isLandscapeEvent && index % 3 === 2
              const tileRatio = isFullWidth ? '4/3' : '3/4'

              return (
                <div
                  key={frame.id}
                  onClick={() => openFrame(index)}
                  style={{
                    aspectRatio: tileRatio,
                    gridColumn: isFullWidth ? '1 / -1' : 'auto',
                    background: '#2a1a10',
                    position: 'relative', borderRadius: 6, overflow: 'hidden',
                    cursor: 'pointer',
                  }}
                >
                  {(frame.thumbnail_url ?? frame.full_url) ? (
                    <img
                      src={frame.thumbnail_url ?? frame.full_url}
                      alt=""
                      loading="lazy"
                      style={{ width: '100%', height: '100%', objectFit: 'cover' }}
                    />
                  ) : null}

                  {/* Guest name */}
                  <div style={{
                    position: 'absolute', bottom: 0, left: 0, right: 0,
                    padding: '28px 8px 6px',
                    background: 'linear-gradient(transparent, rgba(26,23,20,0.65))',
                  }}>
                    <span style={{
                      fontFamily: 'Caveat, cursive', fontSize: 20,
                      color: 'rgba(246,242,232,.95)',
                      textShadow: '0 1px 3px rgba(0,0,0,.55)',
                      display: 'block', paddingLeft: 8,
                    }}>
                      {frame.guest_name}
                    </span>
                  </div>
                </div>
              )
            })}
          </div>

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
    </div>
  )
}
