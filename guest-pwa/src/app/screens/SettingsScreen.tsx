import { useState, type ReactNode } from 'react'
import { useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { EventEdit } from '../components/EventEdit'
import { PayButtons } from '../components/PayBlock'
import { Row } from '../components/Row'
import { formatDate, formatDateTime, guestLink, rubles } from '../format'
import { payUpgrade } from '../payments'
import { qk, useEvent, usePricing } from '../queries'
import { CenterSpinner, copyText, ErrorBox, Icon, icons, Sheet, shareLink, Spinner, toast, TopBar } from '../ui'

type Plan = Schemas['Plan']

/** Повышение тарифа возможно только на следующую ступень (как на сервере). */
const NEXT_PLAN: Partial<Record<Plan, Plan>> = {
  free: 'p10', p10: 'p25', p25: 'p50', p50: 'p75', p75: 'p100', p100: 'p150', p150: 'p175', p175: 'p200', p200: 'p250',
}
const EXTENDED_FRAMES = 45

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <div className="host-field-label" style={{ margin: '4px 2px 8px' }}>{title}</div>
      <div className="host-card">{children}</div>
    </section>
  )
}

function Line({ k, v }: { k: string; v: ReactNode }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 12, padding: '10px 16px' }}>
      <span className="host-muted">{k}</span><b style={{ textAlign: 'right' }}>{v}</b>
    </div>
  )
}

export default function SettingsScreen() {
  const { id = '' } = useParams()
  const qc = useQueryClient()
  const event = useEvent(id)
  const pricing = usePricing()
  const [upgrade, setUpgrade] = useState<'guests' | 'frames' | null>(null)
  const [renameOpen, setRenameOpen] = useState(false)
  const [title, setTitle] = useState('')

  const e = event.data
  const completed = e?.status === 'completed' || e?.status === 'cancelled' || e?.kind === 'solo'

  const share = useQuery({
    queryKey: ['public-share', id],
    enabled: !!e && completed,
    queryFn: async () => (await hostApi.get<Schemas['PublicShareOut']>(`/events/${id}/public-share`)).data,
  })

  const refresh = () => {
    void qc.invalidateQueries({ queryKey: qk.event(id) })
    void qc.invalidateQueries({ queryKey: qk.events })
  }

  const patchSettings = useMutation({
    mutationFn: async (body: Partial<Schemas['EventSettingsUpdateIn']>) => { await hostApi.patch(`/events/${id}/settings`, body) },
    onSuccess: refresh,
    onError: (err) => toast(apiErrorMessage(err)),
  })

  const rename = useMutation({
    mutationFn: async () => { await hostApi.patch(`/events/${id}`, { title: title.trim() }) },
    onSuccess: () => { refresh(); setRenameOpen(false); toast('Название изменено') },
    onError: (err) => toast(apiErrorMessage(err)),
  })

  const openWindow = useMutation({
    mutationFn: async (duration: '2h' | '24h' | '7d') => { await hostApi.post(`/events/${id}/uploads-window`, { duration }) },
    onSuccess: () => { refresh(); toast('Загрузка открыта') },
    onError: (err) => toast(apiErrorMessage(err)),
  })
  const closeWindow = useMutation({
    mutationFn: async () => { await hostApi.delete(`/events/${id}/uploads-window`) },
    onSuccess: () => { refresh(); toast('Загрузка закрыта') },
    onError: (err) => toast(apiErrorMessage(err)),
  })

  const shareAction = useMutation({
    mutationFn: async (action: 'enable' | 'regenerate' | 'delete') => {
      if (action === 'delete') await hostApi.delete(`/events/${id}/public-share`)
      else await hostApi.post(`/events/${id}/public-share/${action}`)
      return action
    },
    onSuccess: (action) => {
      void qc.invalidateQueries({ queryKey: ['public-share', id] })
      toast(action === 'delete' ? 'Открытая ссылка отключена' : action === 'enable' ? 'Открытая ссылка включена' : 'Ссылка обновлена')
    },
    onError: (err) => toast(apiErrorMessage(err)),
  })

  if (event.isLoading || pricing.isLoading) return (<><TopBar back={`/app/events/${id}`} title="Настройки" /><CenterSpinner /></>)
  if (event.error || !e) {
    return (<><TopBar back="/app" title="Настройки" /><main className="host-main"><ErrorBox message={apiErrorMessage(event.error, 'Событие не найдено')} /></main></>)
  }

  const s = e.settings
  const solo = e.kind === 'solo'
  const tiers = pricing.data?.tiers ?? []
  const priceOf = (plan: Plan) => (plan === 'free' ? 0 : tiers.find((t) => t.plan === plan)?.price_kopecks ?? 0)
  const nextPlan = NEXT_PLAN[s.plan]
  const nextTier = nextPlan ? tiers.find((t) => t.plan === nextPlan) : undefined
  const premium = pricing.data?.upgrade_premium ?? 1.15
  const guestsUpgradePrice = nextPlan && nextTier ? Math.round((priceOf(nextPlan) - priceOf(s.plan)) * premium) : 0
  const framesUpgradePrice = s.max_guests * (pricing.data?.frames.price_per_guest_kopecks ?? 0)
  const canUpgrade = e.status === 'active' || e.status === 'completed'
  const canUpgradeFrames = canUpgrade && s.frames_per_guest < EXTENDED_FRAMES && framesUpgradePrice > 0
  const canUpgradeGuests = canUpgrade && !!nextTier && guestsUpgradePrice > 0

  const windowEnds = s.uploads_window_ends_at ? new Date(s.uploads_window_ends_at) : null
  const windowActive = !!windowEnds && windowEnds.getTime() > Date.now()
  const shareUrl = share.data?.public_share_token ? `${window.location.origin}/a/${share.data.public_share_token}` : null
  const link = guestLink(e.short_code)

  return (
    <>
      <TopBar back={`/app/events/${id}`} title="Настройки" kicker={e.title} />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 18 }}>
        <Section title="Событие">
          {solo
            ? <Row icon={icons.settings} label="Название" hint={e.title} onClick={() => { setTitle(e.title); setRenameOpen(true) }} />
            : <EventEdit e={e} />}
        </Section>

        {solo && (
          <Section title="Хранение">
            <Line k="Хранится до" v={e.expires_at ? formatDate(e.expires_at) : '—'} />
            <Row icon={icons.lock} label="Продлить хранение" hint="Альбом останется доступен дольше" to={`/app/events/${id}/extend`} />
          </Section>
        )}

        {!solo && (<>
        <Section title="Тариф">
          <Line k="Гостей" v={`до ${s.max_guests}`} />
          <Line k="Кадров на гостя" v={s.frames_per_guest} />
          <Line k="Хранение до" v={e.expires_at ? formatDate(e.expires_at) : '—'} />
          {canUpgradeGuests && nextTier && (
            <Row icon={icons.users} label={`Больше гостей: до ${nextTier.max_guests}`} hint={`Доплата ${rubles(guestsUpgradePrice)}`} onClick={() => setUpgrade('guests')} />
          )}
          {canUpgradeFrames && (
            <Row icon={icons.camera} label={`Больше кадров: ${EXTENDED_FRAMES} на гостя`} hint={`Доплата ${rubles(framesUpgradePrice)}`} onClick={() => setUpgrade('frames')} />
          )}
          <Row icon={icons.lock} label="Продлить хранение" hint="Альбом останется доступен дольше" to={`/app/events/${id}/extend`} />
        </Section>

        <Section title="Ссылка для гостей">
          <div style={{ padding: '12px 16px', wordBreak: 'break-all' }} className="host-mono">{link}</div>
          <div style={{ display: 'flex', gap: 8, padding: '0 16px 14px' }}>
            <button className="host-chip" onClick={() => void copyText(link, 'Ссылка скопирована')}><Icon d={icons.copy} size={14} /> Копировать</button>
            <button className="host-chip" onClick={() => void shareLink(link, e.title)}><Icon d={icons.share} size={14} /> Отправить</button>
          </div>
        </Section>

        <Section title="Загрузка из галереи">
          {!completed ? (
            <label className="host-row" style={{ cursor: 'pointer' }}>
              <span style={{ flex: 1 }}>
                Гости могут добавлять фото из галереи
                <span className="host-muted" style={{ display: 'block', fontSize: 12 }}>Фильтр плёнки применится на сервере</span>
              </span>
              <input type="checkbox" checked={s.uploads_enabled ?? false} disabled={patchSettings.isPending}
                onChange={(ev) => patchSettings.mutate({ uploads_enabled: ev.target.checked })}
                style={{ width: 22, height: 22, accentColor: 'var(--ink)' }} />
            </label>
          ) : (
            <div style={{ padding: 16 }}>
              {windowActive ? (
                <>
                  <div style={{ marginBottom: 10 }}>Окно загрузки открыто до <b>{formatDateTime(s.uploads_window_ends_at)}</b></div>
                  <button className="btn-ghost btn-sm" disabled={closeWindow.isPending} onClick={() => closeWindow.mutate()}>Закрыть сейчас</button>
                </>
              ) : (
                <>
                  <div className="host-muted" style={{ marginBottom: 10 }}>
                    После завершения гости могут догрузить фото из галереи, пока открыто окно.
                    {!s.uploads_enabled && ' Включить загрузку можно только до завершения события.'}
                  </div>
                  <div style={{ display: 'flex', gap: 8 }}>
                    {([['2h', '2 часа'], ['24h', '24 часа'], ['7d', '7 дней']] as const).map(([d, label]) => (
                      <button key={d} className="host-chip" disabled={openWindow.isPending || !s.uploads_enabled} onClick={() => openWindow.mutate(d)}>{label}</button>
                    ))}
                  </div>
                </>
              )}
            </div>
          )}
        </Section>

        {completed && (
          <Section title="Открытая ссылка на альбом">
            <div style={{ padding: 16 }}>
              {share.isLoading ? <Spinner /> : shareUrl ? (
                <>
                  <div className="host-mono" style={{ wordBreak: 'break-all', marginBottom: 10 }}>{shareUrl}</div>
                  <p className="host-muted" style={{ marginBottom: 12 }}>
                    Любой, у кого есть ссылка, увидит все кадры альбома. Вы отвечаете за её распространение.
                  </p>
                  <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                    <button className="host-chip" onClick={() => void copyText(shareUrl, 'Ссылка скопирована')}><Icon d={icons.copy} size={14} /> Копировать</button>
                    <button className="host-chip" onClick={() => void shareLink(shareUrl, e.title)}><Icon d={icons.share} size={14} /> Отправить</button>
                    <button className="host-chip" disabled={shareAction.isPending} onClick={() => shareAction.mutate('regenerate')}>Обновить</button>
                    <button className="host-chip" style={{ color: 'var(--shutter)' }} disabled={shareAction.isPending} onClick={() => shareAction.mutate('delete')}>Отключить</button>
                  </div>
                </>
              ) : (
                <>
                  <p className="host-muted" style={{ marginBottom: 12 }}>
                    Ссылка выключена. Включив её, вы разрешаете просмотр альбома всем, у кого она будет, и берёте на себя ответственность за её распространение.
                  </p>
                  <button className="btn btn-sm" disabled={shareAction.isPending} onClick={() => shareAction.mutate('enable')}>Включить открытую ссылку</button>
                </>
              )}
            </div>
          </Section>
        )}
        </>)}
      </main>

      <Sheet open={renameOpen} onClose={() => setRenameOpen(false)} title="Название события">
        <input className="input-field" maxLength={80} value={title} onChange={(ev) => setTitle(ev.target.value)} autoFocus />
        <button className="btn" style={{ marginTop: 16 }} disabled={rename.isPending || title.trim().length < 1} onClick={() => rename.mutate()}>
          {rename.isPending ? <Spinner /> : 'Сохранить'}
        </button>
      </Sheet>

      <Sheet open={upgrade === 'guests'} onClose={() => setUpgrade(null)} title="Больше гостей">
        {nextTier && (
          <>
            <p className="host-muted" style={{ marginBottom: 14 }}>
              Тариф вырастет с {s.max_guests} до {nextTier.max_guests} гостей. Доплата за разницу с надбавкой за повышение уже после покупки.
            </p>
            <PayButtons label={`Доплатить ${rubles(guestsUpgradePrice)}`} kind="upgrade_guests" eventId={id}
              expect={{ maxGuests: nextTier.max_guests }} returnTo={`/app/events/${id}/settings`} scope={`up_${id}_guests`}
              run={(method) => payUpgrade(id, 'guests', method)} />
          </>
        )}
      </Sheet>

      <Sheet open={upgrade === 'frames'} onClose={() => setUpgrade(null)} title="Больше кадров">
        <p className="host-muted" style={{ marginBottom: 14 }}>
          Каждому гостю будет доступно {EXTENDED_FRAMES} кадров вместо {s.frames_per_guest}. Доплата считается на {s.max_guests} гостей тарифа.
        </p>
        <PayButtons label={`Доплатить ${rubles(framesUpgradePrice)}`} kind="upgrade_frames" eventId={id}
          expect={{ frames: EXTENDED_FRAMES }} returnTo={`/app/events/${id}/settings`} scope={`up_${id}_frames`}
          run={(method) => payUpgrade(id, 'frames', method)} />
      </Sheet>
    </>
  )
}
