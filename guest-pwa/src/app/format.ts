import type { EventOut } from './api/hostClient'

export const EVENT_TYPE_LABELS: Record<string, string> = {
  wedding: 'Свадьба',
  birthday: 'День рождения',
  corporate: 'Корпоратив',
  party: 'Вечеринка',
  graduation: 'Выпускной',
  travel: 'Путешествие',
  vacation: 'Отпуск',
  concert: 'Концерт',
  other: 'Другое',
}

export const FILM_LABELS: Record<string, { name: string; short: string }> = {
  original: { name: 'Без фильтра', short: 'RAW' },
  portra400: { name: 'Portra 400', short: 'P400' },
  fuji400h: { name: 'Fuji 400H', short: 'F400H' },
  cinestill: { name: 'Cinestill 800T', short: 'CST' },
  ilford: { name: 'Ilford HP5+', short: 'B&W' },
}

export const STATUS_META: Record<string, { label: string; color: string; bg: string }> = {
  draft: { label: 'Черновик', color: 'var(--ink-3)', bg: 'var(--paper)' },
  active: { label: 'Идёт', color: 'var(--shutter)', bg: 'var(--paper)' },
  completed: { label: 'Проявлен', color: 'var(--success)', bg: 'var(--paper)' },
  cancelled: { label: 'Отменён', color: 'var(--ink-4)', bg: 'var(--paper)' },
}

const dateFmt = new Intl.DateTimeFormat('ru-RU', { day: 'numeric', month: 'long', year: 'numeric' })
const shortDateFmt = new Intl.DateTimeFormat('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit' })
const timeFmt = new Intl.DateTimeFormat('ru-RU', { hour: '2-digit', minute: '2-digit' })

export function formatDate(iso?: string | null): string {
  if (!iso) return '—'
  return dateFmt.format(new Date(iso))
}

export function formatShortDate(iso?: string | null): string {
  if (!iso) return '—'
  return shortDateFmt.format(new Date(iso)).replace(/\./g, '·')
}

export function formatDateTime(iso?: string | null): string {
  if (!iso) return '—'
  const d = new Date(iso)
  return `${dateFmt.format(d)}, ${timeFmt.format(d)}`
}

export function rubles(kopecks: number): string {
  return `${new Intl.NumberFormat('ru-RU').format(Math.round(kopecks / 100))} ₽`
}

export function guestLink(shortCode: string): string {
  return `${window.location.origin}/g/${shortCode}`
}

/** Альбом можно открыть организатору: событие завершено/отменено или проявка уже прошла. */
export function albumOpenable(e: EventOut): boolean {
  if (e.status === 'completed' || e.status === 'cancelled') return true
  const revealAt = e.settings.reveal_at
  return !!revealAt && new Date(revealAt).getTime() <= Date.now()
}

export function pluralize(n: number, one: string, few: string, many: string): string {
  const mod10 = n % 10
  const mod100 = n % 100
  if (mod10 === 1 && mod100 !== 11) return one
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few
  return many
}
