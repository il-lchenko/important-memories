import { ZoomPan } from '../../features/album/ZoomPan'
import { useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { GridFormatDialog, MagazineGrid, PolaroidFeed, RetroLayout, ViewSwitcher, type Frame, type ViewMode } from '../../features/album/AlbumScreen'
import { DesktopWall } from '../../features/album/wall/DesktopWalls'
import { useIsDesktop } from '../../features/album/wall/useWall'
import { formatDateTime } from '../format'
import { qk, useEvent, useStyleLock } from '../queries'
import { TITLE_FONTS, parseTitleFont, type TitleFont } from '../styles'
import { BrandIcon, CenterSpinner, ErrorBox, Note, Sheet, shareLink, toast, TopBar } from '../ui'

type AlbumPage = Schemas['AlbumOut']
type AlbumFrame = Schemas['AlbumFrameOut']

const toFrame = (f: AlbumFrame): Frame => ({ ...f, source: f.source === 'upload' ? 'upload' : 'camera' })

/** Фото с поворотом: при 90/270 рамка остаётся прежней, картинка вписывается в повёрнутом виде.
 *  При увеличении поверх превью подгружается оригинал, чтобы разглядеть мелкие детали. */
function RotatedPhoto({ src, fullSrc, rotation }: { src: string; fullSrc: string | null; rotation: number }) {
  const ref = useRef<HTMLDivElement>(null)
  const [box, setBox] = useState({ w: 0, h: 0 })
  const [fullLoaded, setFullLoaded] = useState(false)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    const ro = new ResizeObserver(() => setBox({ w: el.clientWidth, h: el.clientHeight }))
    ro.observe(el)
    setBox({ w: el.clientWidth, h: el.clientHeight })
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

function Viewer({ eventId, frames, index, onIndex, onClose, total }: {
  eventId: string; frames: AlbumFrame[]; index: number; onIndex: (i: number) => void; onClose: () => void; total: number
}) {
  const qc = useQueryClient()
  const frame = frames[index]
  const [confirmDelete, setConfirmDelete] = useState(false)
  const [rot, setRot] = useState<Record<string, number>>({})
  const touch = useRef<number | null>(null)
  const rotation = frame ? (rot[frame.id] ?? frame.rotation ?? 0) : 0

  const rotate = useMutation({
    mutationFn: async (next: number) => { await hostApi.patch(`/events/${eventId}/frames/${frame.id}/rotation`, { rotation: next }) },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: qk.album(eventId) }) },
    onError: (e) => { setRot((r) => { const c = { ...r }; delete c[frame.id]; return c }); toast(apiErrorMessage(e)) },
  })
  const remove = useMutation({
    mutationFn: async () => { await hostApi.delete(`/events/${eventId}/frames/${frame.id}`) },
    onSuccess: () => {
      setConfirmDelete(false)
      void qc.invalidateQueries({ queryKey: qk.album(eventId) })
      void qc.invalidateQueries({ queryKey: qk.event(eventId) })
      toast('Кадр удалён')
      if (frames.length <= 1) onClose(); else onIndex(Math.min(index, frames.length - 2))
    },
    onError: (e) => { setConfirmDelete(false); toast(apiErrorMessage(e)) },
  })

  const prev = () => { if (index > 0) onIndex(index - 1) }
  const next = () => { if (index < frames.length - 1) onIndex(index + 1) }
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (confirmDelete) return
      if (e.key === 'Escape') onClose()
      if (e.key === 'ArrowLeft') prev()
      if (e.key === 'ArrowRight') next()
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  })

  if (!frame) return null
  const doRotate = () => {
    const nextRot = (rotation + 90) % 360
    setRot((r) => ({ ...r, [frame.id]: nextRot }))
    rotate.mutate(nextRot)
  }
  const barBtn = { width: 44, height: 44, borderRadius: '50%', border: '1px solid rgba(240,230,210,.26)', background: 'rgba(255,255,255,.07)', color: '#F0E6D2', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 0 } as const

  return (
    <div className="darkroom" role="dialog" aria-modal="true" aria-label="Просмотр кадра"
      style={{ position: 'fixed', inset: 0, zIndex: 70, display: 'flex', flexDirection: 'column' }}
      onTouchStart={(e) => { touch.current = e.touches[0].clientX }}
      onTouchEnd={(e) => {
        if (touch.current === null) return
        const dx = e.changedTouches[0].clientX - touch.current
        touch.current = null
        if (Math.abs(dx) > 60) { if (dx < 0) next(); else prev() }
      }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: 'calc(10px + env(safe-area-inset-top)) 12px 8px' }}>
        <button style={barBtn} aria-label="Закрыть" onClick={onClose}><BrandIcon name="close" size={22} mono /></button>
        <div style={{ flex: 1, textAlign: 'center', fontSize: 12, letterSpacing: '.14em', color: 'rgba(240,230,210,.6)' }}>
          КАДР {index + 1} ИЗ {total}
        </div>
        <button style={barBtn} aria-label="Повернуть" onClick={doRotate}><BrandIcon name="rotate" size={22} mono /></button>
        <button style={barBtn} aria-label="Поделиться" onClick={() => void shareLink(frame.full_url, frame.guest_name)}><BrandIcon name="share" size={22} mono /></button>
        <a style={{ ...barBtn, textDecoration: 'none' }} aria-label="Скачать оригинал" href={frame.full_url} target="_blank" rel="noreferrer" download><BrandIcon name="download" size={22} mono /></a>
        <button style={barBtn} aria-label="Удалить кадр" onClick={() => setConfirmDelete(true)}><BrandIcon name="trash" size={22} mono /></button>
      </div>

      <div style={{ flex: 1, minHeight: 0, position: 'relative', padding: '0 8px' }}>
        <ZoomPan key={frame.id}>
          {(zoomed) => <RotatedPhoto src={frame.preview_url ?? frame.full_url} fullSrc={zoomed ? frame.full_url : null} rotation={rotation} />}
        </ZoomPan>
        {index > 0 && <button style={{ ...barBtn, position: 'absolute', left: 12, top: '50%' }} aria-label="Предыдущий" onClick={prev}><BrandIcon name="back" size={22} mono /></button>}
        {index < frames.length - 1 && <button style={{ ...barBtn, position: 'absolute', right: 12, top: '50%' }} aria-label="Следующий" onClick={next}><BrandIcon name="next" size={22} mono /></button>}
      </div>

      <div style={{ padding: '10px 20px calc(16px + env(safe-area-inset-bottom))', textAlign: 'center' }}>
        {frame.caption && <div style={{ fontFamily: 'Caveat, cursive', fontSize: 28, marginBottom: 4 }}>{frame.caption}</div>}
        {frame.voice_url && <audio controls src={frame.voice_url} style={{ width: '100%', maxWidth: 420, margin: '6px 0' }} />}
        {frame.note && <p style={{ fontSize: 14, lineHeight: 1.5, color: 'rgba(240,230,210,.85)', maxWidth: 520, margin: '6px auto' }}>{frame.note}</p>}
        <div style={{ fontSize: 13, color: 'rgba(240,230,210,.6)' }}>{frame.guest_name} · {formatDateTime(frame.captured_at)}</div>
      </div>

      <Sheet open={confirmDelete} onClose={() => setConfirmDelete(false)} title="Удалить кадр?">
        <p className="host-muted" style={{ marginBottom: 18 }}>Кадр исчезнет из альбома у всех. У гостя вернётся один кадр в счётчик.</p>
        <button className="btn-danger" disabled={remove.isPending} onClick={() => remove.mutate()} style={{ marginBottom: 10 }}>Удалить</button>
        <button className="btn-ghost" onClick={() => setConfirmDelete(false)}>Отмена</button>
      </Sheet>
    </div>
  )
}

export default function HostAlbumScreen() {
  const { id = '' } = useParams()
  const qc = useQueryClient()
  const desktop = useIsDesktop()
  const [params, setParams] = useSearchParams()
  const event = useEvent(id)
  const [mode, setMode] = useState<ViewMode>('magazine')
  const [columns, setColumns] = useState(desktop ? 4 : 2)
  const [gridDialog, setGridDialog] = useState(false)
  const [fontSheet, setFontSheet] = useState(false)
  const sentinel = useRef<HTMLDivElement>(null)

  const album = useInfiniteQuery({
    queryKey: qk.album(id),
    queryFn: async ({ pageParam }) => (await hostApi.get<AlbumPage>(`/events/${id}/album`, { params: pageParam ? { cursor: pageParam } : {} })).data,
    initialPageParam: null as string | null,
    getNextPageParam: (last) => last.next_cursor,
    refetchInterval: 60_000,
  })

  const items = useMemo(() => album.data?.pages.flatMap((p) => p.items) ?? [], [album.data])
  const frames = useMemo(() => items.map(toFrame), [items])
  const first = album.data?.pages[0]
  const font = parseTitleFont(event.data?.settings.title_font ?? first?.title_font)

  useEffect(() => {
    const el = sentinel.current
    if (!el || !album.hasNextPage) return
    const io = new IntersectionObserver((e) => { if (e[0].isIntersecting && !album.isFetchingNextPage) void album.fetchNextPage() }, { rootMargin: '600px' })
    io.observe(el)
    return () => io.disconnect()
  }, [album.hasNextPage, album.isFetchingNextPage, album])

  const navigate = useNavigate()
  const lock = useStyleLock()
  const saveFont = useMutation({
    mutationFn: async (f: TitleFont) => { await hostApi.patch(`/events/${id}/settings`, { title_font: f }) },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: qk.event(id) }); setFontSheet(false) },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const openId = params.get('f')
  const openIndex = openId ? items.findIndex((f) => f.id === openId) : -1
  const openAt = (i: number) => setParams({ f: items[i].id }, { replace: false })
  const closeViewer = () => setParams({}, { replace: true })

  const title = event.data?.title ?? 'Альбом'
  return (
    <div className="host-wide">
      <TopBar back={`/app/events/${id}`} title={title} right={
        <button className="host-icon-btn" aria-label="Шрифт названия" onClick={() => setFontSheet(true)}>
          <span style={{ fontFamily: 'Playfair Display, serif', fontWeight: 700, fontSize: 16 }}>Aa</span>
        </button>
      } />
      <main className="host-main" style={{ paddingTop: 12 }}>
        {first?.is_admin_preview && (
          <div style={{ marginBottom: 12 }}><Note>Вы видите альбом раньше гостей: они увидят его после проявления.</Note></div>
        )}
        <h1 style={{ ...TITLE_FONTS[font].style, fontSize: 'clamp(32px, 6vw, 56px)', margin: '4px 0 6px' }}>{title}</h1>
        <div className="host-muted" style={{ marginBottom: 14 }}>
          {first?.total_frames ?? 0} кадров · {new Set(items.map((f) => f.guest_id)).size} авторов
        </div>
        <div style={{ maxWidth: 420, marginBottom: 14 }}><ViewSwitcher mode={mode} onChange={setMode} /></div>

        {album.isLoading && <CenterSpinner />}
        {album.error && <ErrorBox message={apiErrorMessage(album.error)} onRetry={() => void album.refetch()} />}
        {!album.isLoading && !album.error && frames.length === 0 && (
          <div className="host-card" style={{ padding: '36px 24px', textAlign: 'center' }}>
            <h2 className="host-h2" style={{ marginBottom: 8 }}>Пока нет кадров</h2>
            <p className="host-muted">Как только гости начнут снимать, кадры появятся здесь.</p>
          </div>
        )}

        {frames.length > 0 && desktop && (
          <DesktopWall mode={mode} frames={frames} eventId={id} onOpenFrame={openAt} />
        )}

        {frames.length > 0 && !desktop && (
          <>
            {mode === 'magazine' && (
              <>
                <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 8 }}>
                  <button className="host-chip" onClick={() => setGridDialog(true)}>Сетка: {columns}</button>
                </div>
                <MagazineGrid frames={frames} columns={columns} onOpenFrame={openAt} onColumnsChange={setColumns} />
              </>
            )}
            {mode === 'retro' && <RetroLayout frames={frames} eventId={id} onOpenFrame={openAt} />}
            {mode === 'polaroid' && <PolaroidFeed frames={frames} onOpenFrame={openAt} />}
          </>
        )}
        <div ref={sentinel} style={{ height: 1 }} />
        {album.isFetchingNextPage && <CenterSpinner />}
      </main>

      {gridDialog && <GridFormatDialog current={columns} onSelect={(c) => { setColumns(c); setGridDialog(false) }} onClose={() => setGridDialog(false)} />}

      {openIndex >= 0 && (
        <Viewer eventId={id} frames={items} index={openIndex} total={first?.total_frames ?? items.length}
          onIndex={(i) => setParams({ f: items[i].id }, { replace: true })} onClose={closeViewer} />
      )}

      <Sheet open={fontSheet} onClose={() => setFontSheet(false)} title="Шрифт названия">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
          {(Object.keys(TITLE_FONTS) as TitleFont[]).map((f) => (
            <button key={f} className="host-card host-row" disabled={saveFont.isPending}
              style={{ border: font === f ? '2px solid var(--amber)' : '2px solid transparent', borderRadius: 12, flexDirection: 'column', alignItems: 'flex-start', gap: 2 }}
              onClick={() => {
                if (lock.fontLocked(f, event.data?.settings.title_font)) { toast('Дополнительные шрифты доступны с подпиской «Плюс»'); navigate('/app/plus'); return }
                saveFont.mutate(f)
              }}>
              <span className="host-muted" style={{ fontSize: 11, letterSpacing: '.1em', textTransform: 'uppercase' }}>{TITLE_FONTS[f].label}{lock.fontLocked(f, event.data?.settings.title_font) ? ' 🔒 Плюс' : ''}</span>
              <span style={{ ...TITLE_FONTS[f].style, fontSize: 26 }}>{title}</span>
            </button>
          ))}
        </div>
      </Sheet>
    </div>
  )
}
