import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi } from '../api/hostClient'
import { useDownloadAll } from '../components/useDownloadAll'
import { Row } from '../components/Row'
import { FILM_LABELS, formatDate } from '../format'
import { startOwnerCamera } from '../ownerCamera'
import { qk, useEntitlements, useEvent, useMe } from '../queries'
import { CenterSpinner, ErrorBox, icons, Sheet, Spinner, toast, TopBar } from '../ui'

/** Личный соло-альбом: без гостей, QR и проявки. */
export default function SoloScreen() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const qc = useQueryClient()
  const event = useEvent(id)
  const ent = useEntitlements().data
  const me = useMe()
  const { downloading, downloadAll } = useDownloadAll(id)
  const [deleteSheet, setDeleteSheet] = useState(false)

  const remove = useMutation({
    mutationFn: async () => { await hostApi.delete(`/events/${id}`) },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: qk.events })
      void qc.invalidateQueries({ queryKey: qk.entitlements })
      navigate('/app', { replace: true })
    },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  if (event.isLoading) return (<><TopBar back="/app" title="Соло-альбом" /><CenterSpinner /></>)
  if (event.error || !event.data) {
    return (<><TopBar back="/app" title="Соло-альбом" /><main className="host-main"><ErrorBox message={apiErrorMessage(event.error, 'Альбом не найден')} onRetry={() => void event.refetch()} /></main></>)
  }

  const e = event.data
  const film = FILM_LABELS[e.settings.lut_preset] ?? FILM_LABELS.original
  const shoot = async () => {
    try {
      const to = await startOwnerCamera(e.short_code, me.data?.display_name ?? '')
      window.location.assign(to)
    } catch (err) {
      toast(apiErrorMessage(err))
    }
  }

  return (
    <>
      <TopBar back="/app" title={e.title} kicker="Соло-альбом" />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div className="host-card" style={{ padding: 16 }}>
          <div style={{ display: 'flex' }}>
            {([[e.frames_count, 'кадров в альбоме'], [film.short, 'плёнка'], [e.expires_at ? formatDate(e.expires_at) : '—', 'хранится до']] as const).map(([v, l]) => (
              <div key={l} style={{ flex: 1, textAlign: 'center' }}>
                <div className="host-mono" style={{ fontSize: 22 }}>{v}</div>
                <div className="host-edge" style={{ fontSize: 11, marginTop: 2 }}>{l}</div>
              </div>
            ))}
          </div>
          {ent && (
            <div style={{ marginTop: 14 }}>
              <div className="host-edge" style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
                <span>Кадров в этом месяце</span>
                <span>{ent.solo_frames_used} из {ent.solo_frames_per_month}</span>
              </div>
              <div style={{ height: 10, border: '1px solid var(--ink)' }}>
                <div style={{ width: `${Math.min(100, Math.round((ent.solo_frames_used / Math.max(1, ent.solo_frames_per_month)) * 100))}%`, height: '100%', background: 'var(--amber)' }} />
              </div>
            </div>
          )}
        </div>

        <div className="host-card">
          <Row icon={icons.camera} label="Снять кадр" hint={ent && ent.solo_frames_left <= 0 ? 'Лимит кадров на месяц исчерпан' : 'Плёночная камера'} onClick={() => void shoot()} />
          <Row icon={icons.albums} label="Открыть альбом" hint="Все кадры" to={`/app/events/${id}/album`} />
          <Row icon={icons.download} label={downloading ? 'Собираем архив…' : 'Скачать все фото'} hint="ZIP со всеми кадрами" onClick={() => void downloadAll()} />
          <Row icon={icons.lock} label="Продлить хранение" hint="Альбом останется доступен дольше" to={`/app/events/${id}/extend`} />
          <Row icon={icons.settings} label="Настройки" hint="Название, оформление" to={`/app/events/${id}/settings`} />
          <Row icon={icons.trash} label="Удалить альбом" danger onClick={() => setDeleteSheet(true)} />
        </div>
      </main>

      <Sheet open={deleteSheet} onClose={() => setDeleteSheet(false)} title="Удалить альбом?">
        <p className="host-muted" style={{ marginBottom: 16 }}>Все кадры альбома будут удалены без возможности восстановления. Освободившиеся места в хранилище вернутся.</p>
        <button className="btn-danger" disabled={remove.isPending} onClick={() => remove.mutate()}>{remove.isPending ? <Spinner /> : 'Удалить навсегда'}</button>
        <button className="btn-ghost" style={{ marginTop: 10 }} onClick={() => setDeleteSheet(false)}>Отмена</button>
      </Sheet>
    </>
  )
}
