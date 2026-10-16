import { hostApi, newIdempotencyKey, type Schemas } from './api/hostClient'

export type PayKind = 'checkout' | 'extend' | 'upgrade_guests' | 'upgrade_frames' | 'subscription'
export type PayMethod = 'sbp' | 'bank_card' | 'yoo_money' | 'sberbank'

const PENDING_KEY = 'im_pay_pending'

export interface PendingPayment {
  eventId: string
  kind: PayKind
  startedAt: number
  /** Что должно стать истиной после оплаты (для опроса статуса). */
  expect: { status?: string; expiresAfter?: string | null; maxGuests?: number; frames?: number; plus?: boolean }
  returnTo: string
}

export function savePending(p: PendingPayment) {
  try { localStorage.setItem(PENDING_KEY, JSON.stringify(p)) } catch { /* ignore */ }
}
export function loadPending(): PendingPayment | null {
  try {
    const raw = localStorage.getItem(PENDING_KEY)
    return raw ? (JSON.parse(raw) as PendingPayment) : null
  } catch { return null }
}
export function clearPending() {
  try { localStorage.removeItem(PENDING_KEY) } catch { /* ignore */ }
}

/** Один ключ идемпотентности на одну и ту же попытку: повторный клик не создаёт второй платёж. */
function keyFor(scope: string): string {
  const k = `im_idem_${scope}`
  try {
    const existing = sessionStorage.getItem(k)
    if (existing) return existing
    const fresh = newIdempotencyKey()
    sessionStorage.setItem(k, fresh)
    return fresh
  } catch { return newIdempotencyKey() }
}
export function resetKey(scope: string) {
  try { sessionStorage.removeItem(`im_idem_${scope}`) } catch { /* ignore */ }
}

export interface PayResult {
  /** admin_bypass или нулевая сумма: платить не нужно, эффект уже применён. */
  done: boolean
  redirectUrl?: string
  amountKopecks: number
}

async function post<T extends { confirmation_url: string; amount_kopecks: number; admin_bypass: boolean }>(
  url: string, body: object, scope: string,
): Promise<PayResult> {
  const { data } = await hostApi.post<T>(url, body, { headers: { 'Idempotency-Key': keyFor(scope) } })
  if (data.admin_bypass || !data.confirmation_url) return { done: true, amountKopecks: data.amount_kopecks }
  return { done: false, redirectUrl: data.confirmation_url, amountKopecks: data.amount_kopecks }
}

export const payCheckout = (eventId: string, plan: Schemas['Plan'], promocode?: string, method?: PayMethod) =>
  post(`/events/${eventId}/checkout`, { plan, promocode: promocode || undefined, payment_method: method }, `co_${eventId}_${plan}_${promocode ?? ''}`)

export const payExtend = (eventId: string, period: '3m' | '6m' | '1y', promocode?: string, method?: PayMethod) =>
  post(`/events/${eventId}/extend`, { period, promocode: promocode || undefined, payment_method: method }, `ex_${eventId}_${period}_${promocode ?? ''}`)

export const payUpgrade = (eventId: string, kind: 'guests' | 'frames', method?: PayMethod) =>
  post(`/events/${eventId}/upgrade`, { kind, payment_method: method }, `up_${eventId}_${kind}`)

/** Уходим на страницу оплаты. Возврат — на /payment/return → /app/payment/return. */
export function goToPayment(url: string, pending: PendingPayment) {
  savePending(pending)
  window.location.assign(url)
}

/** Подписка «Плюс»: ключ идемпотентности один на попытку, платёж создаётся без события. */
export async function paySubscription(period: 'month' | 'year', method?: PayMethod): Promise<PayResult> {
  const { data } = await hostApi.post<{ confirmation_url: string; amount_kopecks: number }>(
    '/subscription/checkout',
    { period, payment_method: method },
    { headers: { 'Idempotency-Key': keyFor(`sub_${period}`) } },
  )
  resetKey(`sub_${period}`)
  return { done: !data.confirmation_url, redirectUrl: data.confirmation_url, amountKopecks: data.amount_kopecks }
}
