import { useMemo, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { Lightbox, type LightboxFrame } from '../components/Lightbox'
import { formatShortDate } from '../format'
import { qk, useCollection, useEvents, useInvitedEvents } from '../queries'
import { CenterSpinner, ErrorBox, Icon, icons, Note, Sheet, Spinner, toast, TopBar } from '../ui'

type CFrame = Schemas['CollectionFrameOut']

export function CreateCollectionScreen() {
  const navigate = useNavigate()
  const qc = useQueryClient()
  const [title, setTitle] = useState('')
  const create = useMutation({
    mutationFn: async () => (await hostApi.post<Schemas['CollectionOut']>('/collections/', { title: title.trim() })).data,
    onSuccess: (c) => {
      void qc.invalidateQueries({ queryKey: qk.collections })
      navigate(`/app/collections/${c.id}/add`, { replace: true })
    },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  return (
    <>
      <TopBar back="/app/new" title="Мини-альбом" kicker="Новая подборка" />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div>
          <label className="host-field-label" htmlFor="col-title">Название</label>
          <input id="col-title" className="input-display" maxLength={80} placeholder="Например, Лучшее за лето"
            value={title} onChange={(e) => setTitle(e.target.value)} autoFocus />
        </div>
        <p className="host-muted">
          В подборку можно собрать кадры из любых ваших альбомов и из альбомов, где вы были гостем. Файлы не копируются,
          поэтому подборка ничего не занимает в хранилище. Если автор удалит кадр или альбом пропадёт по сроку хранения,
          кадр исчезнет и из подборки.
        </p>
        <button className="btn" disabled={create.isPending || title.trim().length < 1} onClick={() => create.mutate()}>
          {create.isPending ? <Spinner /> : 'Создать и выбрать кадры'}
        </button>
      </main>
    </>
  )
}

export function CollectionScreen() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const col = useCollection(id)
  const [open, setOpen] = useState<number | null>(null)
  const [renameSheet, setRenameSheet] = useState(false)
  const [deleteSheet, setDeleteSheet] = useState(false)
  const [title, setTitle] = useState('')

  const refresh = () => {
    void qc.invalidateQueries({ queryKey: qk.collection(id) })
    void qc.invalidateQueries({ queryKey: qk.collections })
  }
  const rename = useMutation({
    mutationFn: async () => { await hostApi.patch(`/collections/${id}`, { title: title.trim() }) },
    onSuccess: () => { refresh(); setRenameSheet(false) },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const remove = useMutation({
    mutationFn: async () => { await hostApi.delete(`/collections/${id}`) },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: qk.collections }); navigate('/app', { replace: true }) },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const removeItem = useMutation({
    mutationFn: async (frameId: string) => { await hostApi.delete(`/collections/${id}/items/${frameId}`) },
    onSuccess: () => { refresh(); setOpen(null) },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const items = col.data?.items ?? []
  const lightFrames = useMemo<LightboxFrame[]>(() => items.map((f) => ({
    id: f.id, preview: f.preview_url ?? f.thumbnail_url ?? null, full: f.full_url, rotation: f.rotation,
    caption: f.caption, subtitle: f.event_title,
  })), [items])

  if (col.isLoading) return (<><TopBar back="/app" title="Мини-альбом" /><CenterSpinner /></>)
  if (col.error || !col.data) {
    return (<><TopBar back="/app" title="Мини-альбом" /><main className="host-main"><ErrorBox message={apiErrorMessage(col.error, 'Подборка не найдена')} /></main></>)
  }
  const c = col.data

  return (
    <>
      <TopBar back="/app" title={c.title} kicker={`Мини-альбом · ${items.length} из ${c.frames_limit}`}
        right={<button className="host-icon-btn" aria-label="Настройки подборки" onClick={() => { setTitle(c.title); setRenameSheet(true) }}><Icon d={icons.settings} /></button>} />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 14 }}>
        <button className="btn" disabled={items.length >= c.frames_limit} onClick={() => navigate(`/app/collections/${id}/add`)}>
          <Icon d={icons.plus} /> Добавить кадры
        </button>
        {items.length >= c.frames_limit && <p className="host-muted">Достигнут лимит кадров в подборке.</p>}
        {c.unavailable_count > 0 && (
          <Note>Недоступно кадров: {c.unavailable_count}. Автор удалил их или срок хранения альбома закончился.</Note>
        )}
        {items.length === 0 && c.unavailable_count === 0 && (
          <div className="host-card" style={{ padding: 24, textAlign: 'center' }}>
            <h2 className="host-h2" style={{ marginBottom: 6 }}>Подборка пуста</h2>
            <p className="host-muted">Выберите кадры из ваших альбомов.</p>
          </div>
        )}
        <div style={{ display: 'grid', gap: 4, gridTemplateColumns: 'repeat(auto-fill, minmax(104px, 1fr))' }}>
          {items.map((f: CFrame, i) => (
            <button key={f.id} onClick={() => setOpen(i)} aria-label="Открыть кадр"
              style={{ aspectRatio: '1', padding: 0, overflow: 'hidden', border: 'none', borderRadius: 12, background: '#1A1714', cursor: 'pointer' }}>
              <img src={f.thumbnail_url ?? f.preview_url ?? f.full_url} alt="" loading="lazy" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
            </button>
          ))}
        </div>
      </main>

      {open !== null && (
        <Lightbox frames={lightFrames} index={Math.min(open, lightFrames.length - 1)} onIndex={setOpen} onClose={() => setOpen(null)}
          onRemove={(f) => removeItem.mutate(f.id)} />
      )}

      <Sheet open={renameSheet} onClose={() => setRenameSheet(false)} title="Подборка">
        <input className="input-field" maxLength={80} value={title} onChange={(e) => setTitle(e.target.value)} />
        <button className="btn" style={{ marginTop: 14 }} disabled={rename.isPending || title.trim().length < 1} onClick={() => rename.mutate()}>
          {rename.isPending ? <Spinner /> : 'Сохранить название'}
        </button>
        <button className="btn-danger" style={{ marginTop: 10 }} onClick={() => { setRenameSheet(false); setDeleteSheet(true) }}>Удалить подборку</button>
      </Sheet>
      <Sheet open={deleteSheet} onClose={() => setDeleteSheet(false)} title="Удалить подборку?">
        <p className="host-muted" style={{ marginBottom: 16 }}>Сами кадры останутся в своих альбомах, пропадёт только подборка.</p>
        <button className="btn-danger" disabled={remove.isPending} onClick={() => remove.mutate()}>{remove.isPending ? <Spinner /> : 'Удалить'}</button>
        <button className="btn-ghost" style={{ marginTop: 10 }} onClick={() => setDeleteSheet(false)}>Отмена</button>
      </Sheet>
    </>
  )
}

type Source = { id: string; title: string; date?: string | null; invited: boolean }

export function CollectionPickerScreen() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const col = useCollection(id)
  const events = useEvents()
  const invited = useInvitedEvents()
  const [sourceId, setSourceId] = useState<string | null>(null)
  const [picked, setPicked] = useState<Set<string>>(new Set())

  const sources = useMemo<Source[]>(() => {
    const mine = (events.data ?? []).filter((e) => e.status !== 'draft' && e.status !== 'cancelled' && e.frames_count > 0)
      .map((e) => ({ id: e.id, title: e.kind === 'solo' ? `${e.title} (соло)` : e.title, date: e.start_at, invited: false }))
    const other = (invited.data ?? []).filter((e) => e.total_frames > 0)
      .map((e) => ({ id: e.id, title: e.title, date: e.start_at, invited: true }))
    return [...mine, ...other]
  }, [events.data, invited.data])

  const activeSource = sourceId ?? sources[0]?.id ?? null

  const album = useInfiniteQuery({
    queryKey: ['picker-album', activeSource],
    enabled: !!activeSource,
    initialPageParam: undefined as string | undefined,
    queryFn: async ({ pageParam }) =>
      (await hostApi.get<Schemas['AlbumOut']>(`/events/${activeSource}/album`, { params: { limit: 60, cursor: pageParam } })).data,
    getNextPageParam: (last) => last.next_cursor ?? undefined,
  })

  const already = useMemo(() => new Set((col.data?.items ?? []).map((f) => f.id)), [col.data])
  const room = (col.data?.frames_limit ?? 0) - already.size
  const frames = album.data?.pages.flatMap((p) => p.items) ?? []
  const notRevealed = album.data?.pages[0] && album.data.pages[0].revealed === false

  const add = useMutation({
    mutationFn: async () => (await hostApi.post<Schemas['CollectionOut']>(`/collections/${id}/items`, { frame_ids: [...picked] })).data,
    onSuccess: (c) => {
      qc.setQueryData(qk.collection(id), c)
      void qc.invalidateQueries({ queryKey: qk.collections })
      navigate(`/app/collections/${id}`, { replace: true })
    },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const toggle = (fid: string) => {
    setPicked((prev) => {
      const next = new Set(prev)
      if (next.has(fid)) next.delete(fid)
      else if (next.size < room) next.add(fid)
      else toast(`В подборке может быть до ${col.data?.frames_limit} кадров`)
      return next
    })
  }

  if (col.isLoading || events.isLoading) return (<><TopBar back={`/app/collections/${id}`} title="Выбрать кадры" /><CenterSpinner /></>)

  return (
    <>
      <TopBar back={`/app/collections/${id}`} title="Выбрать кадры" kicker={col.data?.title} />
      <main className="host-main" style={{ paddingTop: 12, paddingBottom: 120 }}>
        {sources.length === 0 ? (
          <div className="host-card" style={{ padding: 24, textAlign: 'center' }}>
            <h2 className="host-h2" style={{ marginBottom: 6 }}>Пока нечего выбирать</h2>
            <p className="host-muted">Когда в ваших альбомах появятся кадры, их можно будет собрать в подборку.</p>
          </div>
        ) : (
          <>
            <div className="host-scroll-x" style={{ paddingBottom: 12 }}>
              {sources.map((s) => (
                <button key={s.id} className="host-chip" data-active={activeSource === s.id} onClick={() => setSourceId(s.id)}>
                  {s.title}{s.date ? ` · ${formatShortDate(s.date)}` : ''}{s.invited ? ' · гость' : ''}
                </button>
              ))}
            </div>
            {album.isLoading && <CenterSpinner />}
            {album.error && <ErrorBox message={apiErrorMessage(album.error)} onRetry={() => void album.refetch()} />}
            {notRevealed && <p className="host-muted">Этот альбом ещё не открыт, кадры появятся после проявки.</p>}
            <div style={{ display: 'grid', gap: 4, gridTemplateColumns: 'repeat(auto-fill, minmax(104px, 1fr))' }}>
              {frames.map((f) => {
                const taken = already.has(f.id)
                const on = picked.has(f.id)
                return (
                  <button key={f.id} disabled={taken} onClick={() => toggle(f.id)} aria-pressed={on}
                    style={{ aspectRatio: '1', padding: 0, overflow: 'hidden', position: 'relative', borderRadius: 12, border: on ? '3px solid var(--amber)' : 'none', background: '#1A1714', cursor: taken ? 'default' : 'pointer', opacity: taken ? 0.4 : 1 }}>
                    <img src={f.thumbnail_url ?? f.preview_url ?? f.full_url} alt="" loading="lazy" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
                    {on && <span style={{ position: 'absolute', right: 4, top: 4, width: 22, height: 22, borderRadius: 11, background: 'var(--amber)', color: '#fff', fontSize: 13, lineHeight: '22px', textAlign: 'center', fontWeight: 700 }}>✓</span>}
                    {taken && <span className="host-edge" style={{ position: 'absolute', left: 4, bottom: 4, background: 'var(--paper)', padding: '0 4px' }}>в подборке</span>}
                  </button>
                )
              })}
            </div>
            {album.hasNextPage && (
              <button className="btn-ghost btn-sm" style={{ marginTop: 14 }} disabled={album.isFetchingNextPage} onClick={() => void album.fetchNextPage()}>
                {album.isFetchingNextPage ? <Spinner /> : 'Показать ещё'}
              </button>
            )}
          </>
        )}
      </main>
      <div className="host-bottom-bar">
        <div style={{ maxWidth: 720, margin: '0 auto' }}>
          <button className="btn" disabled={picked.size === 0 || add.isPending} onClick={() => add.mutate()}>
            {add.isPending ? <Spinner /> : picked.size ? `Добавить ${picked.size}` : 'Выберите кадры'}
          </button>
        </div>
      </div>
    </>
  )
}
