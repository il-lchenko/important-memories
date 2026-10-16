import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { publicApi } from '../../api/client'
import type { Frame, AlbumOut, ViewMode } from './AlbumScreen'
import {
  ViewSwitcher,
  GridFormatDialog,
  MagazineGrid,
  RetroLayout,
  PolaroidFeed,
  UploadBadge,
} from './AlbumScreen'

const DESKTOP_BP = 1024

function useIsDesktop(): boolean {
  const [isDesktop, setIsDesktop] = useState(() =>
    typeof window !== 'undefined' && window.matchMedia(`(min-width: ${DESKTOP_BP}px)`).matches,
  )
  useEffect(() => {
    const mql = window.matchMedia(`(min-width: ${DESKTOP_BP}px)`)
    const handler = (e: MediaQueryListEvent) => setIsDesktop(e.matches)
    if (mql.addEventListener) mql.addEventListener('change', handler)
    else mql.addListener(handler)
    return () => {
      if (mql.removeEventListener) mql.removeEventListener('change', handler)
      else mql.removeListener(handler)
    }
  }, [])
  return isDesktop
}

function useContainerColumns(ref: React.RefObject<HTMLDivElement | null>): number {
  const [cols, setCols] = useState(4)
  useEffect(() => {
    if (!ref.current) return
    const el = ref.current
    const ro = new ResizeObserver(() => {
      const w = el.getBoundingClientRect().width
      if (w >= 1600) setCols(5)
      else if (w >= 1200) setCols(4)
      else if (w >= 900) setCols(3)
      else setCols(2)
    })
    ro.observe(el)
    return () => ro.disconnect()
  }, [ref])
  return cols
}

export default function PublicAlbumScreen() {
  const { token } = useParams<{ token: string }>()
  const navigate = useNavigate()
  const isDesktop = useIsDesktop()

  const [meta, setMeta] = useState<{ title: string; id: string } | null>(null)
  const [frames, setFrames] = useState<Frame[]>([])
  const [loading, setLoading] = useState(true)
  const [loadingMore, setLoadingMore] = useState(false)
  const [nextCursor, setNextCursor] = useState<string | null>(null)
  const [totalFrames, setTotalFrames] = useState(0)
  const [mode, setMode] = useState<ViewMode>('magazine')
  const [columns, setColumns] = useState(2)
  const [showGridDialog, setShowGridDialog] = useState(false)
  const [notFound, setNotFound] = useState(false)
  const sentinelRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    if (!token) return
    ;(async () => {
      try {
        const { data: metaResp } = await publicApi.getAlbumMeta(token)
        setMeta({ title: metaResp.title, id: metaResp.id })
        setTotalFrames(metaResp.total_frames)
        const { data: page } = await publicApi.listFrames(token)
        const p = page as AlbumOut
        setFrames(p.items)
        setNextCursor(p.next_cursor)
      } catch (e: unknown) {
        const status = (e as { response?: { status?: number } })?.response?.status
        if (status === 404) setNotFound(true)
        else console.error('public_album_failed', e)
      } finally {
        setLoading(false)
      }
    })()
  }, [token])

  useEffect(() => {
    if (!sentinelRef.current || !nextCursor || !token) return
    const observer = new IntersectionObserver((entries) => {
      if (entries[0].isIntersecting && nextCursor && !loadingMore) {
        setLoadingMore(true)
        publicApi.listFrames(token, nextCursor)
          .then(({ data }) => {
            const p = data as AlbumOut
            setFrames((prev) => [...prev, ...p.items])
            setNextCursor(p.next_cursor)
          })
          .catch((e) => console.error('public_album_page_failed', e))
          .finally(() => setLoadingMore(false))
      }
    }, { rootMargin: '200px' })
    observer.observe(sentinelRef.current)
    return () => observer.disconnect()
  }, [nextCursor, loadingMore, token])

  const authorCount = useMemo(
    () => new Set(frames.map((f) => f.guest_id)).size,
    [frames],
  )

  const openFrame = (i: number) => {
    if (!frames[i]) return
    navigate(`/a/${token}/f/${i}`, { state: { frames, totalFrames } })
  }

  const shareLink = async () => {
    const url = window.location.href
    if (navigator.share) {
      try { await navigator.share({ title: meta?.title ?? 'Альбом', url }) } catch {}
      return
    }
    try {
      await navigator.clipboard.writeText(url)
      alert('Ссылка скопирована')
    } catch { /* ignore */ }
  }

  if (notFound) {
    return (
      <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 32, textAlign: 'center' }}>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.16em', color: 'var(--ink-3)', textTransform: 'uppercase', marginBottom: 8 }}>
          АЛЬБОМ НЕ НАЙДЕН
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontWeight: 500, fontSize: isDesktop ? 36 : 26, letterSpacing: '-.02em', margin: 0, color: 'var(--ink)' }}>
          Ссылка неверная или устарела
        </h1>
        <p style={{ marginTop: 12, fontSize: 14, color: 'var(--ink-3)', lineHeight: 1.5, maxWidth: 360 }}>
          Попроси у хоста свежую ссылку — старая перестала работать, если он её обновил.
        </p>
      </div>
    )
  }

  if (isDesktop) {
    return (
      <DesktopAlbum
        meta={meta}
        frames={frames}
        loading={loading}
        loadingMore={loadingMore}
        totalFrames={totalFrames}
        authorCount={authorCount}
        mode={mode}
        onModeChange={setMode}
        onOpenFrame={openFrame}
        onShare={shareLink}
        sentinelRef={sentinelRef}
      />
    )
  }

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)' }}>
      {/* Public banner */}
      <div style={{
        padding: '10px 16px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10,
        background: 'var(--paper-2)',
        borderBottom: '1px solid var(--line)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, minWidth: 0 }}>
          <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--amber)', flexShrink: 0 }} />
          <span style={{
            fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.14em',
            color: 'var(--ink-3)', textTransform: 'uppercase', whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>
            ПУБЛИЧНЫЙ АЛЬБОМ · ПРОСМОТР
          </span>
        </div>
        <button
          onClick={shareLink}
          className="btn-compact btn-compact-ghost"
          style={{ width: 'auto', height: 32, padding: '0 12px', fontSize: 12 }}
        >
          Поделиться
        </button>
      </div>

      {/* Header */}
      <div style={{ padding: '14px 24px 8px' }}>
        <h1 style={{
          fontFamily: 'Fraunces, serif',           fontSize: 26, fontWeight: 500, margin: 0,
          letterSpacing: '-.02em', lineHeight: 1.05, color: 'var(--ink)',
        }}>
          {meta?.title ?? '...'}
        </h1>
        <div style={{
          fontFamily: 'Inter, sans-serif', fontSize: 11,
          letterSpacing: '.14em', color: 'var(--ink-3)',
          textTransform: 'uppercase', marginTop: 4,
        }}>
          {loading ? '...' : `${totalFrames} КАДРОВ · ${authorCount} АВТОРОВ`}
        </div>
      </div>

      {/* Mode switcher */}
      <div style={{ padding: '10px 16px 6px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{ flex: 1 }}>
          <ViewSwitcher mode={mode} onChange={setMode} />
        </div>
        {mode === 'magazine' && (
          <button
            onClick={() => setShowGridDialog(true)}
            aria-label="Формат сетки"
            style={{ width: 44, height: 44, borderRadius: 12, background: 'var(--paper-2)', border: 'none', cursor: 'pointer', color: 'var(--ink)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}
          >
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
              <rect x="3" y="3" width="7" height="7"/><rect x="14" y="3" width="7" height="7"/>
              <rect x="3" y="14" width="7" height="7"/><rect x="14" y="14" width="7" height="7"/>
            </svg>
          </button>
        )}
      </div>

      {loading ? (
        <div style={{ display: 'flex', justifyContent: 'center', padding: 48 }}>
          <span style={{ color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', fontSize: 13 }}>Загрузка...</span>
        </div>
      ) : frames.length === 0 ? (
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '64px 24px', textAlign: 'center' }}>
          <p style={{ fontFamily: 'Fraunces, serif', fontSize: 18, color: 'var(--ink-3)', margin: 0 }}>
            Кадров пока нет
          </p>
        </div>
      ) : (
        <>
          {mode === 'magazine' && (
            <MagazineGrid frames={frames} columns={columns} onOpenFrame={openFrame} onColumnsChange={setColumns} />
          )}
          {mode === 'retro' && meta && (
            <RetroLayout frames={frames} eventId={meta.id} onOpenFrame={openFrame} />
          )}
          {mode === 'polaroid' && (
            <PolaroidFeed frames={frames} onOpenFrame={openFrame} />
          )}
          <div ref={sentinelRef} style={{ height: 1 }} />
          {loadingMore && (
            <div style={{ display: 'flex', justifyContent: 'center', padding: '24px 0' }}>
              <span style={{ color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', fontSize: 12 }}>Загрузка...</span>
            </div>
          )}
        </>
      )}

      {showGridDialog && (
        <GridFormatDialog current={columns} onSelect={setColumns} onClose={() => setShowGridDialog(false)} />
      )}
    </div>
  )
}

/* ────────────────────────── Desktop layout ────────────────────────── */

export function DesktopAlbum({
  meta, frames, loading, loadingMore, totalFrames, authorCount, mode,
  onModeChange, onOpenFrame, onShare, sentinelRef,
}: {
  meta: { title: string; id: string } | null
  frames: Frame[]
  loading: boolean
  loadingMore: boolean
  totalFrames: number
  authorCount: number
  mode: ViewMode
  onModeChange: (m: ViewMode) => void
  onOpenFrame: (i: number) => void
  onShare: () => void
  sentinelRef: React.RefObject<HTMLDivElement | null>
}) {
  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)' }}>
      {/* Thin top bar */}
      <div style={{
        padding: '12px 48px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 16,
        background: 'var(--paper-2)',
        borderBottom: '1px solid var(--line)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <span style={{ width: 7, height: 7, borderRadius: '50%', background: 'var(--amber)' }} />
          <span style={{
            fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.16em',
            color: 'var(--ink-3)', textTransform: 'uppercase',
          }}>
            ПУБЛИЧНЫЙ АЛЬБОМ · ПРОСМОТР
          </span>
        </div>
        <button
          onClick={onShare}
          className="btn-compact btn-compact-ghost"
          style={{ width: 'auto', height: 34, padding: '0 16px', fontSize: 13 }}
        >
          Поделиться
        </button>
      </div>

      {/* Container */}
      <div style={{
        maxWidth: 1400,
        margin: '0 auto',
        padding: '32px 48px 80px',
      }}>
        {/* Hero header */}
        <div style={{ marginBottom: 24 }}>
          <h1 style={{
            fontFamily: 'Fraunces, serif',             fontSize: 'clamp(42px, 5vw, 64px)', fontWeight: 500, margin: 0,
            letterSpacing: '-.03em', lineHeight: 1.02, color: 'var(--ink)',
          }}>
            {meta?.title ?? '...'}
          </h1>
          <div style={{
            fontFamily: 'Inter, sans-serif', fontSize: 12,
            letterSpacing: '.16em', color: 'var(--ink-3)',
            textTransform: 'uppercase', marginTop: 10,
          }}>
            {loading ? '...' : `${totalFrames} КАДРОВ · ${authorCount} АВТОРОВ`}
          </div>
        </div>

        {/* Mode switcher — ограничиваем ширину, чтобы не растягивало на весь экран */}
        <div style={{ maxWidth: 420, marginBottom: 20 }}>
          <ViewSwitcher mode={mode} onChange={onModeChange} />
        </div>

        {loading ? (
          <div style={{ display: 'flex', justifyContent: 'center', padding: 64 }}>
            <span style={{ color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', fontSize: 13 }}>Загрузка...</span>
          </div>
        ) : frames.length === 0 ? (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '96px 24px', textAlign: 'center' }}>
            <p style={{ fontFamily: 'Fraunces, serif', fontSize: 22, color: 'var(--ink-3)', margin: 0 }}>
              Кадров пока нет
            </p>
          </div>
        ) : (
          <>
            {mode === 'magazine' && (
              <DesktopMagazine frames={frames} onOpenFrame={onOpenFrame} />
            )}
            {mode === 'retro' && meta && (
              <div style={{ display: 'flex', justifyContent: 'center' }}>
                <RetroLayout frames={frames} eventId={meta.id} onOpenFrame={onOpenFrame} />
              </div>
            )}
            {mode === 'polaroid' && (
              <div style={{ display: 'flex', justifyContent: 'center' }}>
                <PolaroidFeed frames={frames} onOpenFrame={onOpenFrame} />
              </div>
            )}
            <div ref={sentinelRef} style={{ height: 1 }} />
            {loadingMore && (
              <div style={{ display: 'flex', justifyContent: 'center', padding: '32px 0' }}>
                <span style={{ color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', fontSize: 12 }}>Загрузка...</span>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  )
}

function DesktopMagazine({ frames, onOpenFrame }: {
  frames: Frame[]; onOpenFrame: (i: number) => void;
}) {
  const containerRef = useRef<HTMLDivElement>(null)
  const columns = useContainerColumns(containerRef)
  return (
    <div
      ref={containerRef}
      style={{
        display: 'grid',
        gridTemplateColumns: `repeat(${columns}, 1fr)`,
        gap: 16,
      }}
    >
      {frames.map((frame, i) => (
        <DesktopMagazineCard key={frame.id} frame={frame} onClick={() => onOpenFrame(i)} />
      ))}
    </div>
  )
}

function DesktopMagazineCard({ frame, onClick }: {
  frame: Frame; onClick: () => void;
}) {
  const [hover, setHover] = useState(false)
  const src = frame.preview_url ?? frame.thumbnail_url ?? frame.full_url
  const caption = (frame.caption ?? '').trim()
  return (
    <div
      onClick={onClick}
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      style={{
        position: 'relative',
        aspectRatio: '3 / 4',
        borderRadius: 10,
        overflow: 'hidden',
        background: '#2a1a10',
        cursor: 'pointer',
        boxShadow: hover
          ? '0 10px 28px -8px rgba(26,23,20,.28)'
          : '0 3px 10px -2px rgba(26,23,20,.1)',
        transform: hover ? 'translateY(-2px)' : 'translateY(0)',
        transition: 'transform .18s ease, box-shadow .18s ease',
        border: '0.5px solid var(--line)',
      }}
    >
      <img
        src={src}
        alt=""
        loading="lazy"
        draggable={false}
        style={{
          width: '100%',
          height: '100%',
          objectFit: 'cover',
          transform: hover ? 'scale(1.03)' : 'scale(1)',
          transition: 'transform .25s ease',
          display: 'block',
          userSelect: 'none',
        }}
      />
      {frame.source === 'upload' && <UploadBadge />}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        padding: '28px 14px 12px',
        background: 'linear-gradient(180deg, rgba(0,0,0,0) 0%, rgba(0,0,0,.55) 100%)',
        opacity: hover ? 1 : 0,
        transition: 'opacity .18s ease',
        pointerEvents: 'none',
        display: 'flex',
        alignItems: 'flex-end',
        gap: 8,
      }}>
        <div style={{
          width: 28, height: 28, borderRadius: '50%',
          flexShrink: 0,
          background: frame.guest_avatar_url
            ? `#2a1a10 center/cover no-repeat url(${frame.guest_avatar_url})`
            : 'rgba(255,179,71,.18)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: 'var(--dr-amber, #FFB347)',
          fontFamily: 'Fraunces, serif', fontSize: 13, fontWeight: 600,
          border: '1px solid rgba(255,255,255,.3)',
        }}>
          {!frame.guest_avatar_url && (frame.guest_name?.[0]?.toUpperCase() ?? '?')}
        </div>
        <div style={{
          fontFamily: 'Caveat, cursive',
                    fontSize: caption ? 20 : 18,
          color: '#fff',
          lineHeight: 1.2,
          textShadow: '0 1px 4px rgba(0,0,0,.65)',
          display: '-webkit-box',
          WebkitBoxOrient: 'vertical' as const,
          WebkitLineClamp: 2,
          overflow: 'hidden',
          flex: 1,
        }}>
          {caption || frame.guest_name}
        </div>
      </div>
    </div>
  )
}
