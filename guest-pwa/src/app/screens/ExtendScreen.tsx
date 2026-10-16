import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { apiErrorMessage } from '../api/hostClient'
import { PayButtons, PromoField, type PromoState } from '../components/PayBlock'
import { formatDate, rubles } from '../format'
import { payExtend } from '../payments'
import { useEvent, usePricing } from '../queries'
import { CenterSpinner, ErrorBox, TopBar } from '../ui'

const PERIOD_LABEL: Record<string, string> = { '3m': '3 месяца', '6m': '6 месяцев', '1y': '1 год' }

export default function ExtendScreen() {
  const { id = '' } = useParams()
  const event = useEvent(id)
  const pricing = usePricing()
  const [period, setPeriod] = useState<'3m' | '6m' | '1y'>('3m')
  const [promo, setPromo] = useState<PromoState | null>(null)

  if (event.isLoading || pricing.isLoading) return (<><TopBar back={`/app/events/${id}/settings`} title="Продление" /><CenterSpinner /></>)
  if (event.error || !event.data || !pricing.data) {
    return (<><TopBar back="/app" title="Продление" /><main className="host-main"><ErrorBox message={apiErrorMessage(event.error ?? pricing.error, 'Не удалось загрузить')} /></main></>)
  }

  const e = event.data
  const solo = e.kind === 'solo'
  const options = solo ? pricing.data.solo_extend ?? [] : pricing.data.extend
  const priceOf = (o: { price_kopecks: number; per_guest_kopecks?: number }) =>
    solo ? o.price_kopecks : Math.max(o.price_kopecks, (o.per_guest_kopecks ?? 0) * e.settings.max_guests)
  const opt = options.find((o) => o.period === period) ?? options[0]
  const price = opt ? priceOf(opt) : 0
  const discount = promo ? Math.min(promo.discountKopecks, price) : 0
  const total = price - discount
  const base = e.expires_at && new Date(e.expires_at).getTime() > Date.now() ? new Date(e.expires_at).getTime() : Date.now()
  const newExpires = opt ? new Date(base + opt.days * 86400000).toISOString() : null

  return (
    <>
      <TopBar back={`/app/events/${id}/settings`} title="Продлить хранение" kicker={e.title} />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 14 }}>
        <div className="host-card" style={{ padding: 16 }}>
          <div className="host-edge">Сейчас хранится до</div>
          <div className="host-mono" style={{ fontSize: 22, marginTop: 2 }}>{e.expires_at ? formatDate(e.expires_at) : '—'}</div>
          <p className="host-muted" style={{ marginTop: 8 }}>
            После окончания срока альбом и все кадры будут удалены. Скачайте их заранее или продлите хранение.
          </p>
        </div>

        <div style={{ display: 'grid', gap: 10 }}>
          {options.map((o) => {
            const p = priceOf(o)
            return (
              <button key={o.period} className="host-card" onClick={() => setPeriod(o.period)}
                style={{
                  padding: '14px 16px', display: 'flex', alignItems: 'center', gap: 12, textAlign: 'left', cursor: 'pointer',
                  background: period === o.period ? 'var(--paper-2)' : 'var(--paper)',
                  outline: period === o.period ? '2px solid var(--amber)' : 'none', outlineOffset: 1,
                }}>
                <span style={{ flex: 1 }}>
                  <span className="host-frame-title" style={{ display: 'block', margin: 0, fontSize: 18 }}>{PERIOD_LABEL[o.period] ?? o.period}</span>
                  <span className="host-muted" style={{ fontSize: 13 }}>+{o.days} дн.</span>
                </span>
                <span className="host-mono" style={{ fontSize: 20 }}>{rubles(p)}</span>
              </button>
            )
          })}
        </div>

        {newExpires && (
          <div className="host-muted">Новый срок: <b style={{ color: 'var(--ink)' }}>{formatDate(newExpires)}</b></div>
        )}

        <PromoField kind="extend" eventId={id} period={period} value={promo} onChange={setPromo} />
        <PayButtons
          label={`Оплатить ${rubles(total)}`}
          kind="extend"
          eventId={id}
          expect={{ expiresAfter: e.expires_at }}
          returnTo={`/app/events/${id}/settings`}
          scope={`ex_${id}_${period}_${promo?.code ?? ''}`}
          run={(method) => payExtend(id, period, promo?.code, method)}
        />
      </main>
    </>
  )
}
