import { useMemo, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type EventOut, type Schemas } from '../api/hostClient'
import { PayButtons, PromoField, type PromoState } from '../components/PayBlock'
import { EVENT_TYPE_LABELS, FILM_LABELS, formatDate, rubles } from '../format'
import { payCheckout } from '../payments'
import { qk, useEntitlements, usePricing } from '../queries'
import { Icon, icons, Spinner, toast } from '../ui'

type Pricing = Schemas['PricingOut']

const STEPS = ['Название', 'Кадры', 'Начало', 'Проявка', 'Плёнка', 'Смета'] as const
const FRAME_STOPS = [6, 12, 18, 24, 30]
const GUEST_STOPS = [5, 10, 25, 50, 75, 100, 150, 175, 200, 250]
const PLAN_BY_GUESTS: Record<number, Schemas['Plan']> = {
  5: 'free', 10: 'p10', 25: 'p25', 50: 'p50', 75: 'p75', 100: 'p100', 150: 'p150', 175: 'p175', 200: 'p200', 250: 'p250',
}
const TYPE_ORDER = ['wedding', 'birthday', 'corporate', 'party', 'graduation', 'travel', 'vacation', 'concert', 'other'] as const

interface Draft {
  title: string
  eventType: Schemas['EventType']
  frames: number
  startAt: string   // значение datetime-local или ''
  revealAt: string  // значение datetime-local или ''
  film: Schemas['LutPreset']
  uploads: boolean
}

const toIso = (local: string) => (local ? new Date(local).toISOString() : undefined)

function tierFor(p: Pricing | undefined, guests: number) {
  return p?.tiers.find((t) => t.max_guests === guests)
}

function StepHeader({ step, onClose }: { step: number; onClose: () => void }) {
  return (
    <header className="host-header">
      <div className="host-header-inner" style={{ flexDirection: 'column', alignItems: 'stretch', gap: 10 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <div style={{ flex: 1 }}>
            <div className="host-kicker">Шаг {step + 1} из {STEPS.length} · {STEPS[step]}</div>
            <h1 className="host-h2">Новый альбом</h1>
          </div>
          <button className="host-icon-btn" aria-label="Закрыть" onClick={onClose}><Icon d={icons.close} /></button>
        </div>
        <div style={{ display: 'flex', gap: 4 }} aria-hidden="true">
          {STEPS.map((_, i) => (
            <div key={i} style={{ flex: 1, height: 4, borderRadius: 0, background: i <= step ? 'var(--ink)' : 'var(--paper-3)' }} />
          ))}
        </div>
      </div>
    </header>
  )
}

function Field({ label, children }: { label: string; children: React.ReactNode }) {
  return <div><label className="host-field-label">{label}</label>{children}</div>
}

export default function CreateEventScreen() {
  const navigate = useNavigate()
  const qc = useQueryClient()
  const pricing = usePricing()
  const entitlements = useEntitlements()
  const [step, setStep] = useState(0)
  const [d, setD] = useState<Draft>({ title: '', eventType: 'wedding', frames: 30, startAt: '', revealAt: '', film: 'portra400', uploads: false })
  const [guests, setGuests] = useState(5)
  const [promo, setPromo] = useState<PromoState | null>(null)
  const [busy, setBusy] = useState(false)
  const [createdId, setCreatedId] = useState<string | null>(null)
  const set = <K extends keyof Draft>(k: K, v: Draft[K]) => setD((p) => ({ ...p, [k]: v }))

  const plan = PLAN_BY_GUESTS[guests]
  const tier = tierFor(pricing.data, guests)
  const priceKopecks = tier?.price_kopecks ?? 0
  const discount = promo && priceKopecks > 0 ? Math.min(promo.discountKopecks, priceKopecks) : 0
  const total = priceKopecks - discount
  const isFree = plan === 'free'
  const retention = tier?.retention_days ?? 30

  const stepError = useMemo(() => {
    if (step === 0 && !d.title.trim()) return 'Введите название'
    if (step === 3 && d.revealAt && new Date(d.revealAt) <= new Date()) return 'Время проявки должно быть в будущем'
    if (step === 3 && d.revealAt && d.startAt && new Date(d.revealAt) < new Date(d.startAt)) return 'Проявка не может быть раньше начала'
    return null
  }, [step, d])

  const freeLimitMessage = (): string | null => {
    const e = entitlements.data
    if (!e || !isFree) return null
    if (e.free_active_left === 0) return `Одновременно можно вести ${e.free_active_limit} бесплатных альбома. Удалите ненужный или выберите платный тариф.`
    if (e.free_events_left === 0) return 'Бесплатные альбомы в этом месяце закончились. Новые откроются с 1-го числа, или выберите платный тариф.'
    return null
  }
  const limitMessage = freeLimitMessage()

  const createDraft = async (): Promise<string> => {
    if (createdId) return createdId
    const body = {
      title: d.title.trim(),
      event_type: d.eventType,
      frames_per_guest: d.frames,
      reveal_mode: d.revealAt ? 'delayed' : 'instant',
      reveal_at: toIso(d.revealAt),
      start_at: toIso(d.startAt),
      film: d.film,
      plan,
      uploads_enabled: d.uploads,
    }
    const { data } = await hostApi.post<EventOut>('/events/', body)
    setCreatedId(data.id)
    return data.id
  }

  const finishFree = async () => {
    if (limitMessage) { toast(limitMessage); return }
    setBusy(true)
    try {
      const id = await createDraft()
      await hostApi.post(`/events/${id}/activate`)
      await qc.invalidateQueries({ queryKey: qk.events })
      await qc.invalidateQueries({ queryKey: qk.entitlements })
      navigate(`/app/events/${id}`, { replace: true })
    } catch (e) {
      setBusy(false)
      toast(apiErrorMessage(e))
    }
  }

  const next = () => {
    if (stepError) { toast(stepError); return }
    setStep((s) => Math.min(s + 1, STEPS.length - 1))
  }
  const close = () => navigate('/app')

  return (
    <>
      <StepHeader step={step} onClose={close} />
      <main className="host-main" style={{ paddingTop: 20, display: 'flex', flexDirection: 'column', gap: 18 }}>
        {step === 0 && (
          <>
            <Field label="Название события">
              <input className="input-display" maxLength={80} placeholder="Свадьба Ани и Пети" value={d.title}
                onChange={(e) => set('title', e.target.value)} autoFocus />
            </Field>
            <Field label="Тип события">
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
                {TYPE_ORDER.map((t) => (
                  <button key={t} className="host-chip" data-active={d.eventType === t}
                    style={{ height: 52, justifyContent: 'center', whiteSpace: 'normal', textAlign: 'center', fontSize: 13 }}
                    onClick={() => set('eventType', t)}>{EVENT_TYPE_LABELS[t]}</button>
                ))}
              </div>
            </Field>
          </>
        )}

        {step === 1 && (
          <>
            <p className="host-muted">Сколько кадров может снять каждый гость, как на плёнке: чем меньше, тем ценнее каждый.</p>
            <div className="host-card" style={{ padding: 20 }}>
              <div style={{ fontFamily: 'Playfair Display, serif', fontSize: 56, fontWeight: 600, textAlign: 'center', fontVariantNumeric: 'tabular-nums' }}>{d.frames}</div>
              <div className="host-muted" style={{ textAlign: 'center', marginBottom: 14 }}>кадров на гостя</div>
              <input type="range" min={0} max={FRAME_STOPS.length - 1} step={1} value={FRAME_STOPS.indexOf(d.frames)}
                aria-label="Кадров на гостя" style={{ width: '100%', accentColor: 'var(--amber)' }}
                onChange={(e) => set('frames', FRAME_STOPS[Number(e.target.value)])} />
              <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 6 }}>
                {FRAME_STOPS.map((f) => <span key={f} className="host-muted" style={{ fontSize: 12 }}>{f}</span>)}
              </div>
            </div>
            <p className="host-muted" style={{ fontSize: 13 }}>
              Больше 30 кадров можно добавить позже в настройках альбома: +{rubles(pricing.data?.frames.price_per_guest_kopecks ?? 1000)} за каждого гостя.
            </p>
          </>
        )}

        {step === 2 && (
          <>
            <p className="host-muted">Когда гости смогут начать снимать. Если пропустить, съёмка откроется сразу после запуска.</p>
            <Field label="Начало съёмки">
              <input className="input-field" type="datetime-local" value={d.startAt} onChange={(e) => set('startAt', e.target.value)} />
            </Field>
            {d.startAt && <button className="btn-ghost btn-sm" onClick={() => set('startAt', '')}>Пропустить шаг</button>}
          </>
        )}

        {step === 3 && (
          <>
            <p className="host-muted">Когда кадры «проявятся» и станут видны всем. Если пропустить, вы откроете альбом вручную.</p>
            <Field label="Время проявки">
              <input className="input-field" type="datetime-local" value={d.revealAt} onChange={(e) => set('revealAt', e.target.value)} />
            </Field>
            {d.revealAt && <button className="btn-ghost btn-sm" onClick={() => set('revealAt', '')}>Пропустить шаг</button>}
          </>
        )}

        {step === 4 && (
          <>
            <Field label="Плёнка">
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {(Object.keys(FILM_LABELS) as Schemas['LutPreset'][]).map((f) => (
                  <button key={f} className="host-card host-row" style={{ border: d.film === f ? '2px solid var(--amber)' : '2px solid transparent', borderRadius: 2 }}
                    onClick={() => set('film', f)}>
                    <span style={{ flex: 1, fontWeight: 600 }}>{FILM_LABELS[f].name}</span>
                    <span className="host-muted" style={{ fontSize: 12 }}>{FILM_LABELS[f].short}</span>
                  </button>
                ))}
              </div>
            </Field>
            <label className="host-card" style={{ padding: 16, display: 'flex', gap: 12, alignItems: 'center', cursor: 'pointer' }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontWeight: 600 }}>Загрузка из галереи</div>
                <div className="host-muted" style={{ fontSize: 12 }}>Гости смогут добавлять фото не только с камеры. Можно изменить позже.</div>
              </div>
              <input type="checkbox" role="switch" checked={d.uploads} onChange={(e) => set('uploads', e.target.checked)} style={{ width: 44, height: 26, accentColor: 'var(--amber)' }} />
            </label>
          </>
        )}

        {step === 5 && (
          <>
            <Field label="Сколько будет гостей">
              <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: 8 }}>
                {GUEST_STOPS.map((g) => {
                  const t = tierFor(pricing.data, g)
                  return (
                    <button key={g} className="host-chip" data-active={guests === g} onClick={() => { setGuests(g); setPromo(null) }}
                      style={{ height: 58, flexDirection: 'column', justifyContent: 'center', gap: 2, padding: 0 }}>
                      <span style={{ fontWeight: 700, fontSize: 16 }}>{g}</span>
                      <span style={{ fontSize: 10, opacity: .75 }}>{t ? (t.price_kopecks === 0 ? 'бесплатно' : rubles(t.price_kopecks)) : '…'}</span>
                    </button>
                  )
                })}
              </div>
              {pricing.data && (
                <p className="host-muted" style={{ fontSize: 12, marginTop: 8 }}>
                  Больше {pricing.data.tiers[pricing.data.tiers.length - 1].max_guests} гостей: {rubles(pricing.data.custom.base_price_kopecks)} + {rubles(pricing.data.custom.per_guest_kopecks)} за каждого сверх. Напишите нам на support@impomento.pro.
                </p>
              )}
            </Field>

            <div className="host-card" style={{ padding: 16 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0' }}><span className="host-muted">Событие</span><b>{d.title.trim()}</b></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0' }}><span className="host-muted">Тариф</span><b>до {guests} гостей</b></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0' }}><span className="host-muted">Кадров на гостя</span><b>{d.frames}</b></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0' }}><span className="host-muted">Плёнка</span><b>{FILM_LABELS[d.film].name}</b></div>
              <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0' }}>
                <span className="host-muted">Хранение</span>
                <b>{retention} дн. · до {formatDate(new Date(Date.now() + retention * 86400000).toISOString())}</b>
              </div>
              {discount > 0 && <div style={{ display: 'flex', justifyContent: 'space-between', padding: '4px 0' }}><span className="host-muted">Скидка</span><b>−{rubles(discount)}</b></div>}
              <div style={{ borderTop: '1px dashed var(--ink-4)', margin: '10px 0' }} />
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline' }}>
                <span style={{ fontWeight: 600 }}>Итого</span>
                <span style={{ fontFamily: 'Playfair Display, serif', fontSize: 28, fontWeight: 600 }}>{isFree ? 'Бесплатно' : rubles(total)}</span>
              </div>
            </div>

            {!isFree && (
              <PromoField kind="checkout" plan={plan} value={promo} onChange={setPromo} />
            )}
            {isFree && entitlements.data && entitlements.data.free_events_left !== null && !limitMessage && (
              <p className="host-muted" style={{ fontSize: 13 }}>
                Бесплатных альбомов осталось в этом месяце: {entitlements.data.free_events_left}.
              </p>
            )}
            {limitMessage && <div className="host-card" style={{ padding: 14, color: 'var(--shutter)', fontSize: 14 }}>{limitMessage}</div>}
            <p className="host-muted" style={{ fontSize: 12 }}>
              Продление хранения и больше кадров можно купить позже в настройках альбома.
            </p>
          </>
        )}
      </main>

      <div className="footer-gradient" style={{ position: 'fixed', left: 0, right: 0, bottom: 0, zIndex: 40, padding: '16px 16px calc(16px + env(safe-area-inset-bottom))' }}>
        <div style={{ width: '100%', maxWidth: 720, margin: '0 auto', display: 'flex', flexDirection: 'column', gap: 8 }}>
          {step < STEPS.length - 1 && (
            <div style={{ display: 'flex', gap: 8 }}>
              {step > 0 && <button className="btn-ghost" style={{ width: 120 }} onClick={() => setStep((s) => s - 1)}>Назад</button>}
              <button className="btn" onClick={next}>
                {step === 4 ? 'К смете' : step === 2 || step === 3 ? ((step === 2 ? d.startAt : d.revealAt) ? 'Далее' : 'Пропустить') : 'Далее'}
                <Icon d={icons.chevron} size={18} />
              </button>
            </div>
          )}
          {step === STEPS.length - 1 && (
            <>
              {isFree ? (
                <button className="btn" disabled={busy || !!limitMessage || pricing.isLoading} onClick={() => void finishFree()}>
                  {busy ? <Spinner style={{ borderColor: 'rgba(255,255,255,.3)', borderTopColor: '#fff' }} /> : 'Создать бесплатно'}
                </button>
              ) : (
                <CreateAndPay
                  label={`Оплатить ${rubles(total)}`}
                  createDraft={createDraft}
                  plan={plan}
                  promo={promo?.code}
                  expect={{ status: 'active' }}
                  disabled={pricing.isLoading}
                />
              )}
              <button className="btn-ghost btn-sm" onClick={() => setStep((s) => s - 1)}>Назад</button>
            </>
          )}
        </div>
      </div>
    </>
  )
}

/** Для платного тарифа черновик создаётся перед оплатой, затем уходим на страницу платёжной системы. */
function CreateAndPay({ label, createDraft, plan, promo, expect, disabled }: {
  label: string
  createDraft: () => Promise<string>
  plan: Schemas['Plan']
  promo?: string
  expect: { status?: string }
  disabled?: boolean
}) {
  const [eventId, setEventId] = useState<string | null>(null)
  const [preparing, setPreparing] = useState(false)

  if (!eventId) {
    return (
      <button className="btn" disabled={disabled || preparing} onClick={async () => {
        setPreparing(true)
        try { setEventId(await createDraft()) } catch (e) { toast(apiErrorMessage(e)) } finally { setPreparing(false) }
      }}>
        {preparing ? <Spinner style={{ borderColor: 'rgba(255,255,255,.3)', borderTopColor: '#fff' }} /> : 'Перейти к оплате'}
      </button>
    )
  }
  return (
    <PayButtons
      label={label}
      kind="checkout"
      eventId={eventId}
      expect={expect}
      returnTo={`/app/events/${eventId}`}
      scope={`co_${eventId}_${plan}_${promo ?? ''}`}
      run={(method) => payCheckout(eventId, plan, promo, method)}
    />
  )
}
