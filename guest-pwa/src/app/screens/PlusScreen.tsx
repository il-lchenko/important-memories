import { useState, type ReactNode } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi } from '../api/hostClient'
import { formatDate, rubles } from '../format'
import { paySubscription, goToPayment } from '../payments'
import { qk, usePricing, useSubscription } from '../queries'
import { BrandIcon, CenterSpinner, ErrorBox, Spark, Spinner, toast, TopBar } from '../ui'

function Feature({ children }: { children: ReactNode }) {
  return (
    <div style={{ display: 'flex', gap: 10, padding: '9px 0', borderBottom: '1px solid var(--line)', lineHeight: 1.45 }}>
      <span style={{ paddingTop: 3 }}><Spark size={15} /></span><span>{children}</span>
    </div>
  )
}

/** ImpoMento Плюс: что входит, цена, оформление и отмена. */
export default function PlusScreen() {
  const qc = useQueryClient()
  const sub = useSubscription()
  const plus = usePricing().data?.plus
  const [period, setPeriod] = useState<'month' | 'year'>('year')
  const [busy, setBusy] = useState(false)

  const cancel = useMutation({
    mutationFn: async () => { await hostApi.post('/subscription/cancel') },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: qk.subscription }); void qc.invalidateQueries({ queryKey: qk.entitlements }); toast('Автопродление выключено') },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const resume = useMutation({
    mutationFn: async () => { await hostApi.post('/subscription/resume') },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: qk.subscription }); toast('Автопродление включено') },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  if (sub.isLoading) return (<><TopBar back="/app/profile" title="Плюс" /><CenterSpinner /></>)
  if (sub.error || !sub.data) {
    return (<><TopBar back="/app/profile" title="Плюс" /><main className="host-main"><ErrorBox message={apiErrorMessage(sub.error)} onRetry={() => void sub.refetch()} /></main></>)
  }
  const s = sub.data
  const monthly = s.month_kopecks
  const yearly = s.year_kopecks
  const yearPerMonth = Math.round(yearly / 12)
  const saving = Math.round((1 - yearly / (monthly * 12)) * 100)

  const buy = async () => {
    setBusy(true)
    try {
      const r = await paySubscription(period)
      goToPayment(r.redirectUrl!, { eventId: '', kind: 'subscription', startedAt: Date.now(), expect: { plus: true }, returnTo: '/app/plus' })
    } catch (e) {
      setBusy(false)
      toast(apiErrorMessage(e))
    }
  }

  return (
    <>
      <TopBar back="/app/profile" title="ImpoMento Плюс" kicker={s.plus && s.status ? 'Подписка активна' : 'Подписка'} />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 16 }}>
        {s.plus && s.status && (
          <div className="host-card" style={{ padding: 16, borderLeft: '3px solid var(--success)' }}>
            <div className="host-edge">Статус</div>
            <div style={{ fontWeight: 600, marginTop: 4 }}>
              {s.cancel_at_period_end ? 'Не продлится' : 'Продлевается автоматически'}
            </div>
            <div className="host-muted" style={{ marginTop: 4 }}>
              Действует до {s.current_period_end ? formatDate(s.current_period_end) : '—'}
              {s.period === 'year' ? ' (годовая)' : ' (месячная)'}
            </div>
            <div style={{ marginTop: 12 }}>
              {s.cancel_at_period_end ? (
                <button className="btn btn-sm" disabled={resume.isPending} onClick={() => resume.mutate()}>Включить автопродление</button>
              ) : (
                <button className="btn-ghost btn-sm" disabled={cancel.isPending} onClick={() => cancel.mutate()}>Отменить автопродление</button>
              )}
            </div>
          </div>
        )}

        <div className="host-card" style={{ padding: '20px 18px', display: 'flex', alignItems: 'center', gap: 16, background: 'var(--paper-2)' }}>
          <BrandIcon name="plus" size={56} />
          <div className="host-muted" style={{ lineHeight: 1.5 }}>Больше места для личных альбомов, подборки без границ и оформление, которого нет у других.</div>
        </div>

        <div className="host-card" style={{ padding: 16 }}>
          <div className="host-edge">Что входит</div>
          {plus && (
            <>
              <Feature>Соло-альбомы: до <b>{plus.solo_frames_per_month}</b> кадров в месяц вместо {plus.solo_free_frames_per_month}, хранятся, пока действует подписка (без подписки {Math.round(plus.solo_free_retention_days / 30)} мес.)</Feature>
              <Feature>События на 5 гостей: {plus.events_active} одновременно и {plus.events_per_month} в месяц вместо {plus.free_events_active} и {plus.free_events_per_month}</Feature>
              <Feature>Мини-альбомы без ограничения по числу (вместо {plus.mini_free_albums}), до {plus.mini_frames_per_album} кадров в подборке вместо {plus.mini_free_frames_per_album}</Feature>
            </>
          )}
          <Feature>Дополнительные QR-стили, шрифты названия и темы оформления альбома</Feature>
          <Feature>Страница альбома по ссылке без отметки ImpoMento</Feature>
          <Feature>Все новые функции первыми</Feature>
        </div>

        {!s.enabled && (
          <div className="host-card" style={{ padding: 16, background: 'var(--paper-2)' }}>
            <b>Скоро.</b>
            <p className="host-muted" style={{ marginTop: 4 }}>Подписка пока не запущена: все возможности из списка работают без оплаты, пока мы заканчиваем подключение платежей.</p>
          </div>
        )}

        {s.enabled && !(s.plus && !s.cancel_at_period_end) && (
          <>
            <div style={{ display: 'grid', gap: 10 }}>
              {([['year', 'На год', yearly, `${rubles(yearPerMonth)} в месяц, выгода ${saving}%`], ['month', 'На месяц', monthly, 'Продлевается каждый месяц']] as const).map(([p, label, price, hint]) => (
                <button key={p} className="host-card" onClick={() => setPeriod(p)}
                  style={{ padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12, textAlign: 'left', cursor: 'pointer', background: period === p ? 'var(--paper-2)' : 'var(--paper)', outline: period === p ? '2px solid var(--amber)' : 'none', outlineOffset: 1 }}>
                  <span style={{ flex: 1 }}>
                    <span className="host-frame-title" style={{ display: 'block', margin: 0, fontSize: 18 }}>{label}</span>
                    <span className="host-muted" style={{ fontSize: 13 }}>{hint}</span>
                  </span>
                  <span className="host-mono" style={{ fontSize: 22 }}>{rubles(price)}</span>
                </button>
              ))}
            </div>
            <button className="btn" disabled={busy} onClick={() => void buy()}>
              {busy ? <Spinner /> : `Оформить за ${rubles(period === 'year' ? yearly : monthly)}`}
            </button>
            <p className="host-muted" style={{ fontSize: 12.5 }}>
              Оплата банковской картой с сохранением способа оплаты для автопродления. Отменить можно в любой момент здесь же:
              доступ сохранится до конца оплаченного периода. Условия в <a href="/offer.html" target="_blank" rel="noreferrer">оферте</a>.
            </p>
          </>
        )}
      </main>
    </>
  )
}
