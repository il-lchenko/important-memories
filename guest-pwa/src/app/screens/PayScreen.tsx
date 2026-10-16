import { useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { apiErrorMessage } from '../api/hostClient'
import { PayButtons, PromoField, type PromoState } from '../components/PayBlock'
import { FILM_LABELS, formatDate, rubles } from '../format'
import { payCheckout } from '../payments'
import { useEvent, usePricing } from '../queries'
import { CenterSpinner, ErrorBox, TopBar } from '../ui'

/** Оплата уже созданного черновика (тариф выбран при создании). */
export default function PayScreen() {
  const { id = '' } = useParams()
  const navigate = useNavigate()
  const event = useEvent(id)
  const pricing = usePricing()
  const [promo, setPromo] = useState<PromoState | null>(null)

  if (event.isLoading || pricing.isLoading) return (<><TopBar back={`/app/events/${id}`} title="Оплата" /><CenterSpinner /></>)
  if (event.error || !event.data) {
    return (<><TopBar back="/app" title="Оплата" /><main className="host-main"><ErrorBox message={apiErrorMessage(event.error, 'Событие не найдено')} /></main></>)
  }
  const e = event.data
  const plan = e.settings.plan
  const tier = pricing.data?.tiers.find((t) => t.plan === plan)
  if (e.status !== 'draft') { navigate(`/app/events/${id}`, { replace: true }); return null }
  if (!tier || tier.price_kopecks === 0) { navigate(`/app/events/${id}`, { replace: true }); return null }

  const discount = promo ? Math.min(promo.discountKopecks, tier.price_kopecks) : 0
  const total = tier.price_kopecks - discount

  return (
    <>
      <TopBar back={`/app/events/${id}`} title="Оплата" kicker="Запуск события" />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div className="host-card" style={{ padding: 16 }}>
          <div style={{ fontFamily: 'Playfair Display, serif', fontSize: 22, fontWeight: 600, marginBottom: 10 }}>{e.title}</div>
          {([
            ['Тариф', `до ${tier.max_guests} гостей`],
            ['Кадров на гостя', String(e.settings.frames_per_guest)],
            ['Плёнка', FILM_LABELS[e.settings.lut_preset]?.name ?? '—'],
            ['Хранение', `${tier.retention_days} дн. · до ${formatDate(new Date(Date.now() + tier.retention_days * 86400000).toISOString())}`],
          ] as const).map(([k, v]) => (
            <div key={k} style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0' }}><span className="host-muted">{k}</span><b>{v}</b></div>
          ))}
          {discount > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0' }}><span className="host-muted">Скидка</span><b>−{rubles(discount)}</b></div>}
          <div style={{ borderTop: '1px solid var(--line)', margin: '10px 0' }} />
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
            <span style={{ fontWeight: 600 }}>Итого</span>
            <span style={{ fontFamily: 'Playfair Display, serif', fontSize: 28, fontWeight: 600 }}>{rubles(total)}</span>
          </div>
        </div>
        <PromoField kind="checkout" eventId={id} plan={plan} value={promo} onChange={setPromo} />
        <PayButtons
          label={`Оплатить ${rubles(total)}`}
          kind="checkout"
          eventId={id}
          expect={{ status: 'active' }}
          returnTo={`/app/events/${id}`}
          scope={`co_${id}_${plan}_${promo?.code ?? ''}`}
          run={(method) => payCheckout(id, plan, promo?.code, method)}
        />
      </main>
    </>
  )
}
