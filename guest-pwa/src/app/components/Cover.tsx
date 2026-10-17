import { useRef, useState, type ReactNode } from 'react'
import { useInfiniteQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type EventOut, type Schemas } from '../api/hostClient'
import { qk } from '../queries'
import { BrandIcon, Icon, icons, Sheet, Spinner, toast } from '../ui'

/** Всё про обложку альбома или подборки: загрузка из галереи, первый кадр, выбор из кадров. */
export function useCover(id: string, kind: 'event' | 'collection' = 'event') {
  const qc = useQueryClient()
  const base = kind === 'event' ? `/events/${id}` : `/collections/${id}`
  const done = (data: { cover_url?: string | null }) => {
    if (kind === 'event') {
      qc.setQueryData(qk.event(id), (old: EventOut | undefined) => (old ? { ...old, cover_url: data.cover_url ?? null } : old))
      void qc.invalidateQueries({ queryKey: qk.event(id) })
      void qc.invalidateQueries({ queryKey: qk.events })
    } else {
      void qc.invalidateQueries({ queryKey: qk.collection(id) })
      void qc.invalidateQueries({ queryKey: qk.collections })
    }
    toast('Обложка обновлена')
  }
  const upload = useMutation({
    mutationFn: async (file: File) => {
      const form = new FormData()
      form.append('file', file)
      return (await hostApi.post<{ cover_url?: string | null }>(`${base}/cover`, form)).data
    },
    onSuccess: done,
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const fromFrame = useMutation({
    mutationFn: async (frameId: string | null) =>
      (await hostApi.post<{ cover_url?: string | null }>(`${base}/cover/from-frame`, { frame_id: frameId })).data,
    onSuccess: done,
    onError: (e) => toast(apiErrorMessage(e)),
  })
  return { upload, fromFrame, pending: upload.isPending || fromFrame.isPending }
}

type CoverApi = ReturnType<typeof useCover>

export interface PickFrame { id: string; thumb: string }

function FramePicker({ eventId, list, onPick, onBack }: { eventId: string; list?: PickFrame[]; onPick: (id: string) => void; onBack: () => void }) {
  const q = useInfiniteQuery({
    enabled: !list,
    queryKey: ['cover-frames', eventId],
    initialPageParam: undefined as string | undefined,
    queryFn: async ({ pageParam }) =>
      (await hostApi.get<Schemas['AlbumOut']>(`/events/${eventId}/album`, { params: { limit: 60, cursor: pageParam } })).data,
    getNextPageParam: (p) => p.next_cursor ?? undefined,
  })
  const frames: PickFrame[] = list ?? (q.data?.pages.flatMap((p) => p.items) ?? []).map((f) => ({ id: f.id, thumb: f.thumbnail_url ?? f.preview_url ?? f.full_url }))
  return (
    <>
      <button className="host-text-btn" style={{ marginBottom: 8 }} onClick={onBack}>← Назад</button>
      {!list && q.isLoading && <div style={{ padding: 24, textAlign: 'center' }}><Spinner /></div>}
      {!list && q.error && <p className="host-muted">{apiErrorMessage(q.error)}</p>}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 4, maxHeight: '55vh', overflowY: 'auto' }}>
        {frames.map((f) => (
          <button key={f.id} onClick={() => onPick(f.id)} aria-label="Сделать обложкой"
            style={{ padding: 0, border: 'none', aspectRatio: '1', borderRadius: 10, overflow: 'hidden', cursor: 'pointer', background: 'var(--paper-3)' }}>
            <img src={f.thumb} alt="" loading="lazy" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
          </button>
        ))}
      </div>
      {!list && q.hasNextPage && <button className="btn-ghost btn-sm" style={{ marginTop: 10 }} disabled={q.isFetchingNextPage} onClick={() => void q.fetchNextPage()}>Ещё</button>}
    </>
  )
}

/** Лист «Обложка альбома»: три понятных способа. */
export function CoverSheet({ eventId, open, onClose, framesCount, hasCover, api, frames }: {
  eventId: string; open: boolean; onClose: () => void; framesCount: number; hasCover: boolean; api: CoverApi
  /** Для подборки: кадры, из которых можно выбрать обложку. */
  frames?: PickFrame[]
}) {
  const fileRef = useRef<HTMLInputElement>(null)
  const [mode, setMode] = useState<'menu' | 'frames'>('menu')
  const close = () => { setMode('menu'); onClose() }
  const choice = (icon: string | ReactNode, title: string, text: string, onClick: () => void, disabled?: boolean) => (
    <button className="host-card host-row" style={{ borderRadius: 16, textAlign: 'left', opacity: disabled ? 0.5 : 1 }} disabled={disabled} onClick={onClick}>
      <span style={{ color: 'var(--amber)', display: 'flex' }}>{typeof icon === 'string' ? <Icon d={icon} size={24} /> : icon}</span>
      <span style={{ flex: 1 }}>
        <span style={{ display: 'block', fontWeight: 700 }}>{title}</span>
        <span className="host-muted" style={{ display: 'block', fontSize: 12.5, marginTop: 1 }}>{text}</span>
      </span>
    </button>
  )
  return (
    <>
      <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" hidden
        onChange={(ev) => { const f = ev.target.files?.[0]; ev.target.value = ''; if (f) { close(); api.upload.mutate(f) } }} />
      <Sheet open={open} onClose={close} title={mode === 'menu' ? (hasCover ? 'Сменить обложку' : 'Обложка альбома') : 'Выберите кадр'}>
        {mode === 'menu' ? (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
            {choice(<BrandIcon name="gallery" size={26} />, 'Загрузить из галереи', 'Любое фото с телефона или компьютера', () => fileRef.current?.click())}
            {choice(icons.camera, 'Взять первый кадр альбома', framesCount > 0 ? 'Самый первый снятый кадр станет обложкой' : 'Появится после первого снимка',
              () => { close(); api.fromFrame.mutate(frames ? frames[0]?.id ?? null : null) }, framesCount === 0)}
            {choice(icons.frames, 'Выбрать из кадров', framesCount > 0 ? 'Любой кадр из альбома' : 'Появится после первого снимка', () => setMode('frames'), framesCount === 0)}
          </div>
        ) : (
          <FramePicker eventId={eventId} list={frames} onBack={() => setMode('menu')} onPick={(id) => { close(); api.fromFrame.mutate(id) }} />
        )}
      </Sheet>
    </>
  )
}

/** Плашка под обложкой, пока её нет: сразу загрузить или взять первый кадр. */
export function CoverPrompt({ eventId, framesCount, api, onOpen, firstFrameId }: { eventId: string; framesCount: number; api: CoverApi; onOpen: () => void; firstFrameId?: string | null }) {
  const key = `im_cover_prompt_${eventId}`
  const [hidden, setHidden] = useState(() => { try { return localStorage.getItem(key) === '1' } catch { return false } })
  if (hidden) return null
  const hide = () => { try { localStorage.setItem(key, '1') } catch { /* без хранилища плашка вернётся */ } setHidden(true) }
  const hasFrames = framesCount > 0
  const fileRef = useRef<HTMLInputElement>(null)
  return (
    <div className="host-card" style={{ padding: 16, position: 'relative', background: 'var(--paper-2)' }}>
      <input ref={fileRef} type="file" accept="image/jpeg,image/png,image/webp" hidden
        onChange={(ev) => { const f = ev.target.files?.[0]; ev.target.value = ''; if (f) api.upload.mutate(f) }} />
      <button className="host-icon-btn" aria-label="Скрыть" onClick={hide}
        style={{ position: 'absolute', top: 6, right: 6, width: 32, height: 32, background: 'transparent' }}><Icon d={icons.close} size={18} /></button>
      <div className="host-edge">Обложка</div>
      <div style={{ fontFamily: "'Playfair Display', serif", fontSize: 20, fontWeight: 600, margin: '4px 28px 4px 0' }}>
        {hasFrames ? 'Сделайте первый кадр обложкой' : 'Добавьте обложку альбома'}
      </div>
      <p className="host-muted" style={{ fontSize: 13.5, marginBottom: 12 }}>
        {hasFrames
          ? 'В альбоме уже есть кадры. Одно нажатие, и самый первый станет обложкой, либо загрузите своё фото.'
          : 'Загрузите фото сейчас. Либо после первого снимка мы предложим сделать его обложкой одним нажатием.'}
      </p>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        {hasFrames && (
          <button className="btn btn-sm" style={{ flex: '1 1 180px' }} disabled={api.pending} onClick={() => api.fromFrame.mutate(firstFrameId ?? null)}>
            {api.fromFrame.isPending ? <Spinner /> : 'Взять первый кадр'}
          </button>
        )}
        <button className={hasFrames ? 'btn-ghost btn-sm' : 'btn btn-sm'} style={{ flex: '1 1 180px' }} disabled={api.pending} onClick={hasFrames ? onOpen : () => fileRef.current?.click()}>
          {api.upload.isPending ? <Spinner /> : hasFrames ? 'Другие способы' : 'Загрузить из галереи'}
        </button>
      </div>
    </div>
  )
}
