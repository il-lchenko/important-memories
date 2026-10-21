import { replaceEqualDeep } from '@tanstack/react-query'

/**
 * Сервер при каждом ответе подписывает ссылки на фото заново, поэтому при каждом фоновом
 * обновлении (раз в 30–60 секунд) у каждой картинки меняется адрес, и браузер загружает все
 * фото заново: страница «мигает». Здесь прежний адрес сохраняется, пока он указывает на тот же
 * файл и срок его жизни не исчерпан наполовину.
 */
const SIGNED = /[?&]X-Amz-Signature=/i

const pathOf = (u: string): string => u.split('?')[0]

function stillFresh(url: string, now: number): boolean {
  const d = /[?&]X-Amz-Date=(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})Z/.exec(url)
  const e = /[?&]X-Amz-Expires=(\d+)/.exec(url)
  if (!d || !e) return false
  const issued = Date.UTC(+d[1], +d[2] - 1, +d[3], +d[4], +d[5], +d[6])
  return now < issued + Number(e[1]) * 1000 * 0.5
}

type Obj = Record<string, unknown>
const isObj = (x: unknown): x is Obj => typeof x === 'object' && x !== null && !Array.isArray(x)

export function keepStableUrls(prev: unknown, next: unknown, now: number = Date.now()): unknown {
  if (typeof next === 'string') {
    if (typeof prev === 'string' && prev !== next && SIGNED.test(next) && pathOf(prev) === pathOf(next) && stillFresh(prev, now)) {
      return prev
    }
    return next
  }
  if (Array.isArray(next)) {
    if (!Array.isArray(prev)) return next
    const byId = new Map<unknown, unknown>()
    for (const x of prev) if (isObj(x) && 'id' in x) byId.set(x.id, x)
    return next.map((x, i) => {
      const before = isObj(x) && 'id' in x ? byId.get(x.id) : prev[i]
      return before === undefined ? x : keepStableUrls(before, x, now)
    })
  }
  if (isObj(next)) {
    if (!isObj(prev)) return next
    const out: Obj = {}
    for (const k of Object.keys(next)) out[k] = keepStableUrls(prev[k], next[k], now)
    return out
  }
  return next
}

/** Для `structuralSharing` в React Query: те же данные с прежними адресами картинок и общей структурой. */
export function stableStructuralSharing(oldData: unknown, newData: unknown): unknown {
  if (oldData === undefined) return newData
  return replaceEqualDeep(oldData, keepStableUrls(oldData, newData))
}
