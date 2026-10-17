import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type EventOut, type Schemas } from '../api/hostClient'
import {
  EVENT_TYPE_LABELS, FILM_LABELS, STATUS_META, albumOpenable, formatDate, formatDateTime, formatShortDate, guestLink,
} from '../format'
import { CoverPrompt, CoverSheet, useCover } from '../components/Cover'
import { Row } from '../components/Row'
import { useGalleryUpload } from '../components/useGalleryUpload'
import { startOwnerCamera } from '../ownerCamera'
import { qk, useEvent, useMe } from '../queries'
import { BrandIcon, CenterSpinner, copyText, DarkroomCard, ErrorBox, Icon, icons, Sheet, shareLink, Spinner, toast, TopBar } from '../ui'

function Metric({ value, label }: { value: string | number; label: string }) {
  return (
    <div style={{ flex: 1, textAlign: 'center', padding: '12px 4px' }}>
      <div className="host-mono" style={{ fontSize: 24 }}>{value}</div>
      <div className="host-edge" style={{ fontSize: 11, marginTop: 2 }}>{label}</div>
    </div>
  )
}

function PinCard({ eventId }: { eventId: string }) {
  const qc = useQueryClient()
  const [shown, setShown] = useState(false)
  const pin = useQuery({
    queryKey: ['pin', eventId],
    queryFn: async () => (await hostApi.get<Schemas['EventPinOut']>(`/events/${eventId}/pin`)).data,
  })
  const update = useMutation({
    mutationFn: async (body: { enabled: boolean; pin?: string | null }) =>
      (await hostApi.patch<Schemas['EventPinOut']>(`/events/${eventId}/pin`, body)).data,
    onSuccess: (data) => { qc.setQueryData(['pin', eventId], data); void qc.invalidateQueries({ queryKey: qk.event(eventId) }) },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const enabled = pin.data?.pin_enabled ?? false
  return (
    <div className="host-card" style={{ padding: 16 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <span style={{ color: 'var(--amber)', display: 'flex' }}><Icon d={icons.lock} size={20} /></span>
        <div style={{ flex: 1 }}>
          <div style={{ fontWeight: 600 }}>PIN-код на вход</div>
          <div className="host-muted" style={{ fontSize: 12 }}>{enabled ? 'Гости вводят код после сканирования' : 'Выключен: войти может любой, у кого есть ссылка'}</div>
        </div>
        <label style={{ display: 'inline-flex', cursor: 'pointer' }}>
          <input type="checkbox" role="switch" aria-label="PIN-код" checked={enabled} disabled={update.isPending || pin.isLoading}
            onChange={(e) => update.mutate({ enabled: e.target.checked })}
            style={{ width: 44, height: 26, accentColor: 'var(--amber)' }} />
        </label>
      </div>
      {enabled && pin.data?.entry_pin && (
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 14 }}>
          <div style={{ flex: 1, fontFamily: 'Inter, sans-serif', fontSize: 24, fontWeight: 700, letterSpacing: '.3em', fontVariantNumeric: 'tabular-nums' }}>
            {shown ? pin.data.entry_pin : '• • • •'}
          </div>
          <button className="host-chip" onClick={() => setShown((v) => !v)}>{shown ? 'Скрыть' : 'Показать'}</button>
          <button className="host-chip" onClick={() => void copyText(pin.data!.entry_pin!, 'PIN скопирован')}>Копировать</button>
          <button className="host-chip" disabled={update.isPending} onClick={() => update.mutate({ enabled: true, pin: null })}>Новый</button>
        </div>
      )}
    </div>
  )
}

function JoinStats({ eventId }: { eventId: string }) {
  const stats = useQuery({
    queryKey: ['join-stats', eventId],
    queryFn: async () => (await hostApi.get<Schemas['JoinStatsOut']>(`/events/${eventId}/join-stats`)).data,
  })
  const d = stats.data
  if (!d || d.total === 0) return null
  return (
    <div className="host-card" style={{ padding: 16, outline: d.suspicious ? '1px solid rgba(213,75,61,.45)' : undefined }}>
      <div style={{ fontWeight: 600, marginBottom: 4 }}>
        Входы за {d.window_hours} ч{d.suspicious && <span style={{ color: 'var(--shutter)' }}> · подозрительная активность</span>}
      </div>
      <div className="host-muted" style={{ fontSize: 13, lineHeight: 1.6 }}>
        Всего {d.total}, успешно {d.ok}. Неверный код: {d.bad_code}, неверный PIN: {d.bad_pin}, ограничено: {d.rate_limited}. Уникальных устройств: {d.unique_fingerprints}.
      </div>
    </div>
  )
}

export default function EventScreen() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const event = useEvent(id)
  const me = useMe()
  const gallery = useGalleryUpload(id, event.data?.short_code ?? '', me.data?.display_name ?? '')
  const [revealSheet, setRevealSheet] = useState(false)
  const [deleteSheet, setDeleteSheet] = useState(false)
  const [downloading, setDownloading] = useState(false)

  const refresh = () => { void qc.invalidateQueries({ queryKey: qk.event(id) }); void qc.invalidateQueries({ queryKey: qk.events }) }
  const reveal = useMutation({
    mutationFn: async () => (await hostApi.post<EventOut>(`/events/${id}/reveal`)).data,
    onSuccess: () => { refresh(); setRevealSheet(false); toast('Альбом открыт') },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const activate = useMutation({
    mutationFn: async () => (await hostApi.post<EventOut>(`/events/${id}/activate`)).data,
    onSuccess: () => { refresh(); toast('Событие запущено') },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const remove = useMutation({
    mutationFn: async () => { await hostApi.delete(`/events/${id}`) },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: qk.events }); navigate('/app', { replace: true }) },
    onError: (e) => { setDeleteSheet(false); toast(apiErrorMessage(e)) },
  })
  const cover = useCover(id)
  const [coverSheet, setCoverSheet] = useState(false)

  const downloadAll = async () => {
    setDownloading(true)
    try {
      const { data: job } = await hostApi.post<Schemas['ArchiveJobOut']>(`/events/${id}/download`)
      for (let i = 0; i < 90; i++) {
        await new Promise((r) => setTimeout(r, 2000))
        const { data } = await hostApi.get<Schemas['ArchiveJobOut']>(`/events/${id}/download/${job.job_id}`)
        if (data.status === 'ready' && data.download_url) { window.location.assign(data.download_url); return }
        if (data.status === 'empty') { toast('В альбоме пока нет фото'); return }
        if (data.status === 'failed') { toast('Не удалось собрать архив'); return }
      }
      toast('Архив собирается слишком долго, попробуйте позже')
    } catch (e) {
      toast(apiErrorMessage(e))
    } finally {
      setDownloading(false)
    }
  }

  if (event.isLoading) return (<><TopBar back="/app" title="Событие" /><CenterSpinner /></>)
  if (event.error || !event.data) {
    return (<><TopBar back="/app" title="Событие" /><main className="host-main"><ErrorBox message={apiErrorMessage(event.error, 'Событие не найдено')} onRetry={() => void event.refetch()} /></main></>)
  }

  const e = event.data
  const s = e.settings
  const meta = STATUS_META[e.status] ?? STATUS_META.draft
  const openable = albumOpenable(e)
  const link = guestLink(e.short_code)
  const film = FILM_LABELS[s.lut_preset] ?? FILM_LABELS.original
  const isFreePlan = s.plan === 'free'

  const shoot = async () => {
    try {
      const to = await startOwnerCamera(e.short_code, me.data?.display_name ?? '')
      window.location.assign(to)
    } catch (err) {
      toast(apiErrorMessage(err))
    }
  }
  const openAlbum = () => (openable ? navigate(`/app/events/${id}/album`) : setRevealSheet(true))
  const payNow = () => navigate(`/app/events/${id}/pay`)

  return (
    <>
      {gallery.input}
      <main className="host-main" style={{ paddingTop: 'calc(14px + env(safe-area-inset-top))', display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div>
          <div className="host-cover">
            {e.cover_url && <img src={e.cover_url} alt="" />}
            <div style={{ position: 'absolute', inset: 0, background: 'linear-gradient(180deg, transparent 45%, rgba(0,0,0,.53))' }} />
            <div style={{ position: 'absolute', top: 12, left: 12, right: 12, display: 'flex', justifyContent: 'space-between' }}>
              <button className="host-glass" aria-label="Назад" onClick={() => navigate('/app')}><Icon d={icons.back} /></button>
              <div style={{ display: 'flex', gap: 8 }}>
                {e.cover_url && (
                  <button className="host-glass host-glass-pill" aria-label="Сменить обложку" disabled={cover.pending} onClick={() => setCoverSheet(true)}>
                    {cover.pending ? <Spinner /> : <><BrandIcon name="cover" size={22} light /><span>Обложка</span></>}
                  </button>
                )}
                <button className="host-glass" aria-label="Настройки альбома" onClick={() => navigate(`/app/events/${id}/settings`)}><Icon d={icons.settings} /></button>
              </div>
            </div>
            <div style={{ position: 'absolute', left: 14, bottom: 14 }}>
              <span className="host-badge" style={{ color: meta.color }}>{meta.label}</span>
            </div>
            {!e.cover_url && (
              <button className="host-cover-cta" disabled={cover.pending} onClick={() => setCoverSheet(true)}>
                {cover.pending ? <Spinner /> : <><BrandIcon name="cover" size={26} light /><span>Добавить обложку</span></>}
              </button>
            )}
          </div>
          <div style={{ padding: '14px 4px 0' }}>
            <h1 className="host-title" style={{ fontWeight: 500, fontSize: 28, letterSpacing: '-.5px' }}>{e.title}</h1>
            <div className="host-muted" style={{ marginTop: 6, fontSize: 13 }}>
              {EVENT_TYPE_LABELS[e.event_type] ?? 'Событие'} · {formatDate(e.start_at)}
              {e.expires_at && <> · хранится до {formatShortDate(e.expires_at)}</>}
            </div>
          </div>
        </div>

        {!e.cover_url && e.status !== 'cancelled' && (
          <CoverPrompt eventId={id} framesCount={e.frames_count ?? 0} api={cover} onOpen={() => setCoverSheet(true)} />
        )}
        <CoverSheet eventId={id} open={coverSheet} onClose={() => setCoverSheet(false)} framesCount={e.frames_count ?? 0} hasCover={!!e.cover_url} api={cover} />

        <div className="host-card host-metrics">
          <Metric value={`${e.guests_count ?? 0}/${s.max_guests}`} label="гостей" />
          <Metric value={e.frames_count ?? 0} label="кадров" />
          <Metric value={s.frames_per_guest} label="на гостя" />
          <Metric value={film.short} label="плёнка" />
        </div>

        {e.status === 'draft' && (
          <DarkroomCard
            kicker="Черновик · ещё не запущено"
            title={isFreePlan ? 'Плёнка заряжена, осталось запустить' : 'Осталось оплатить и запустить'}
            stages={[{ label: 'Создано', state: 'done' }, { label: isFreePlan ? 'Запуск' : 'Оплата', state: 'now' }, { label: 'Съёмка', state: 'next' }]}
          >
            <p className="host-darkroom-text">
              {isFreePlan ? 'После запуска появится QR-код: гости сканируют его и снимают на ваш альбом.' : 'Оплатите выбранный тариф, и событие запустится, а гости получат QR-код.'}
            </p>
            {isFreePlan
              ? <button className="btn" disabled={activate.isPending} onClick={() => activate.mutate()}>{activate.isPending ? <Spinner /> : 'Запустить бесплатно'}</button>
              : <button className="btn" onClick={payNow}>Оплатить и запустить</button>}
          </DarkroomCard>
        )}

        {e.status !== 'draft' && e.status !== 'cancelled' && (
          <div className="host-card">
            <Row icon={icons.qr} label="QR-код для гостей" hint="Покажите на экране или отправьте" to={`/app/events/${id}/qr`} />
            {(e.status === 'active' || e.status === 'completed') && (
              <Row icon={<BrandIcon name="gallery" size={24} />} label={gallery.busy ? `Добавляем фото: ${gallery.progress ?? ''}` : 'Добавить фото из галереи'} hint="Ваши снимки появятся в альбоме с плёночным фильтром" onClick={gallery.pick} />
            )}
            {e.status === 'active' && <Row icon={icons.camera} label="Снять кадр" hint="Вы тоже можете снимать в этом альбоме" onClick={() => void shoot()} />}
            <Row icon={icons.albums} label="Открыть альбом" hint={openable ? 'Все кадры гостей' : s.reveal_at ? `Откроется ${formatDateTime(s.reveal_at)}` : 'Пока закрыт для просмотра'} onClick={openAlbum} />
            {e.status === 'active' && <Row icon={icons.users} label="Гости и ход съёмки" to={`/app/events/${id}/progress`} />}
            {e.status === 'active' && <Row icon={icons.camera} label="Открыть альбом сейчас" hint="Завершить съёмку и проявить кадры" onClick={() => setRevealSheet(true)} />}
            <Row icon={icons.mail} label="Пригласить лично" hint="Персональная ссылка для гостя" to={`/app/events/${id}/invites`} />
            <Row icon={icons.download} label={downloading ? 'Собираем архив…' : 'Скачать все фото'} hint="ZIP со всеми кадрами" onClick={() => { if (!downloading) void downloadAll() }} />
          </div>
        )}

        {e.status !== 'draft' && e.status !== 'cancelled' && (
          <div className="host-card" style={{ padding: 16 }}>
            <div style={{ fontWeight: 600, marginBottom: 8 }}>Ссылка для гостей</div>
            <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 14, wordBreak: 'break-all', color: 'var(--ink-2)', marginBottom: 12 }}>{link}</div>
            <div style={{ display: 'flex', gap: 8 }}>
              <button className="btn-ghost btn-sm" onClick={() => void copyText(link, 'Ссылка скопирована')}><Icon d={icons.copy} size={16} /> Копировать</button>
              <button className="btn-ghost btn-sm" onClick={() => void shareLink(link, e.title)}><Icon d={icons.share} size={16} /> Поделиться</button>
            </div>
          </div>
        )}

        {(e.status === 'active' || e.status === 'completed') && <PinCard eventId={id} />}
        {e.status === 'active' && <JoinStats eventId={id} />}

        {e.status !== 'cancelled' && (
          <div className="host-card">
            <Row icon={icons.settings} label="Настройки альбома" hint="Тариф, ссылка для просмотра, загрузка из галереи" to={`/app/events/${id}/settings`} />
            {e.status !== 'active' && <Row icon={icons.trash} label="Удалить событие" danger onClick={() => setDeleteSheet(true)} />}
          </div>
        )}
      </main>

      <Sheet open={revealSheet} onClose={() => setRevealSheet(false)} title="Открыть альбом сейчас?">
        <p className="host-muted" style={{ marginBottom: 18 }}>
          {e.status === 'active'
            ? 'Съёмка завершится, кадры проявятся, и гости увидят альбом.'
            : s.reveal_at ? `Альбом откроется ${formatDateTime(s.reveal_at)}. Можно открыть сразу.` : 'Альбом пока закрыт для просмотра.'}
        </p>
        <button className="btn" disabled={reveal.isPending} onClick={() => reveal.mutate()} style={{ marginBottom: 10 }}>Открыть сейчас</button>
        {e.status === 'active' && <button className="btn-ghost" onClick={() => navigate(`/app/events/${id}/settings`)} style={{ marginBottom: 10 }}>Назначить время проявки</button>}
        <button className="btn-ghost" onClick={() => setRevealSheet(false)}>Отмена</button>
      </Sheet>
      <Sheet open={deleteSheet} onClose={() => setDeleteSheet(false)} title="Удалить событие?">
        <p className="host-muted" style={{ marginBottom: 18 }}>Событие пропадёт из списка. Это действие нельзя отменить.</p>
        <button className="btn-danger" disabled={remove.isPending} onClick={() => remove.mutate()} style={{ marginBottom: 10 }}>Удалить</button>
        <button className="btn-ghost" onClick={() => setDeleteSheet(false)}>Отмена</button>
      </Sheet>
    </>
  )
}

