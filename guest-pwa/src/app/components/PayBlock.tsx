import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { rubles } from '../format'
import { goToPayment, resetKey, type PayKind, type PayMethod, type PayResult, type PendingPayment } from '../payments'
import { qk } from '../queries'
import { Spinner, toast } from '../ui'

export interface PromoState { code: string; discountKopecks: number }

/** Поле промокода: проверяет код на сервере и сообщает скидку. */
export function PromoField({ kind, eventId, plan, period, upgradeKind, value, onChange }: {
  kind: 'checkout' | 'extend' | 'upgrade'
  eventId?: string
  plan?: string
  period?: string
  upgradeKind?: 'guests' | 'frames'
  value: PromoState | null
  onChange: (p: PromoState | null) => void
}) {
  const [code, setCode] = useState('')
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  if (value) {
    return (
      <div className="host-card" style={{ padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 10, background: 'rgba(106,146,105,.12)' }}>
        <div style={{ flex: 1, fontSize: 14 }}>
          Промокод <b>{value.code}</b>: −{rubles(value.discountKopecks)}
        </div>
        <button className="host-chip" onClick={() => { onChange(null); setCode('') }}>Убрать</button>
      </div>
    )
  }

  const apply = async () => {
    const c = code.trim().toUpperCase()
    if (!c) return
    setBusy(true); setError(null)
    try {
      const { data } = await hostApi.post<Schemas['ValidatePromocodeOut']>('/promocodes/validate', {
        code: c, kind, event_id: eventId, plan, period, upgrade_kind: upgradeKind,
      })
      if (data.valid) onChange({ code: c, discountKopecks: data.discount_kopecks })
      else setError(data.error ?? 'Промокод не подходит')
    } catch (e) {
      setError(apiErrorMessage(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <div>
      <div style={{ display: 'flex', gap: 8 }}>
        <input className="input-field" style={{ height: 48, flex: 1, textTransform: 'uppercase' }} placeholder="Промокод"
          value={code} onChange={(e) => setCode(e.target.value)} onKeyDown={(e) => { if (e.key === 'Enter') void apply() }} />
        <button className="btn-ghost btn-sm" style={{ width: 120 }} disabled={busy || !code.trim()} onClick={() => void apply()}>
          {busy ? <Spinner /> : 'Применить'}
        </button>
      </div>
      {error && <div style={{ color: 'var(--shutter)', fontSize: 13, marginTop: 6 }}>{error}</div>}
    </div>
  )
}

/** Кнопка оплаты: «через СБП» + «другой способ». После оплаты возвращает на returnTo. */
export function PayButtons({ label, run, kind, eventId, expect, returnTo, scope, disabled }: {
  label: string
  run: (method?: PayMethod) => Promise<PayResult>
  kind: PayKind
  eventId: string
  expect: PendingPayment['expect']
  returnTo: string
  scope: string
  disabled?: boolean
}) {
  const navigate = useNavigate()
  const qc = useQueryClient()
  const [busy, setBusy] = useState(false)

  const go = async (method?: PayMethod) => {
    setBusy(true)
    try {
      const r = await run(method)
      resetKey(scope)
      if (r.done) {
        await qc.invalidateQueries({ queryKey: qk.events })
        await qc.invalidateQueries({ queryKey: qk.event(eventId) })
        toast('Готово')
        navigate(returnTo, { replace: true })
        return
      }
      goToPayment(r.redirectUrl!, { eventId, kind, startedAt: Date.now(), expect, returnTo })
    } catch (e) {
      setBusy(false)
      toast(apiErrorMessage(e))
    }
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      <button className="btn" disabled={busy || disabled} onClick={() => void go('sbp')}>
        {busy ? <Spinner style={{ borderColor: 'rgba(255,255,255,.3)', borderTopColor: '#fff' }} /> : `${label} через СБП`}
      </button>
      <button className="btn-ghost btn-sm" disabled={busy || disabled} onClick={() => void go(undefined)}>Другой способ оплаты</button>
    </div>
  )
}
