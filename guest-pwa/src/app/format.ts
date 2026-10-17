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

export const FILM_LABELS: Record<string, { name: string; short: string; desc: string }> = {
  original: { name: 'Без фильтра', short: 'RAW', desc: 'Фото как снято · Без обработки' },
  portra400: { name: 'Kodak Portra 400', short: 'P400', desc: 'Тёплые телесные тона · Лучше всего для свадеб' },
  fuji400h: { name: 'Fuji 400H', short: 'F400H', desc: 'Холодные пастельные зелёные · Природа и портреты' },
  cinestill: { name: 'Cinestill 800T', short: 'CST', desc: 'Неоновые красные · Ночные и городские сцены' },
  ilford: { name: 'Ilford HP5+', short: 'B&W', desc: 'Ч/Б · Классика документальной съёмки' },
}

export const STATUS_META: Record<string, { label: string; color: string; bg: string }> = {
  draft: { label: 'Черновик', color: '#B0A080', bg: '' },
  active: { label: 'Запись', color: '#C9881E', bg: '' },
  completed: { label: 'Проявлено', color: '#5BAA72', bg: '' },
  cancelled: { label: 'Отменён', color: '#9C9082', bg: '' },
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
