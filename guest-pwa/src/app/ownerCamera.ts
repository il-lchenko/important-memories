import { deviceFingerprint, hostApi } from './api/hostClient'

interface OwnerSession {
  guest_token: string
  guest_id: string
  event: unknown
}

/**
 * Организатор снимает в своём альбоме как обычный гость: сервер выдаёт гостевую сессию
 * по токену организатора (без PIN и без ожидания начала). Дальше работает гостевая камера.
 */
export async function startOwnerCamera(shortCode: string, displayName: string): Promise<string> {
  const name = displayName.trim() || 'Организатор'
  const { data } = await hostApi.post<OwnerSession>('/guest/sessions', {
    short_code: shortCode,
    name,
    fingerprint: deviceFingerprint(),
  })
  const ev = JSON.stringify(data.event)
  try {
    sessionStorage.setItem('guest_token', data.guest_token)
    sessionStorage.setItem('guest_id', data.guest_id)
    sessionStorage.setItem('guest_name', name)
    sessionStorage.setItem('event', ev)
    localStorage.setItem(`gt_${shortCode}`, data.guest_token)
    localStorage.setItem(`gi_${shortCode}`, data.guest_id)
    localStorage.setItem(`gn_${shortCode}`, name)
    localStorage.setItem(`ge_${shortCode}`, ev)
  } catch { /* приватный режим: сессия останется только в памяти вкладки */ }
  return `/g/${shortCode}/camera`
}
