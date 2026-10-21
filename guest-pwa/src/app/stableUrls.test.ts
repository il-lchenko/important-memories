import { describe, expect, it } from 'vitest'
import { keepStableUrls, stableStructuralSharing } from './stableUrls'

const NOW = Date.UTC(2026, 9, 22, 12, 0, 0)
const url = (name: string, issuedHour: number, sig: string, expires = 86400) =>
  `https://impomento.pro/s3/im/${name}.webp?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Date=20261022T${String(issuedHour).padStart(2, '0')}0000Z&X-Amz-Expires=${expires}&X-Amz-Signature=${sig}`

describe('keepStableUrls', () => {
  it('keeps the previous signed URL for the same file while it is fresh', () => {
    const prev = { items: [{ id: 'a', thumb: url('a', 11, 'old') }] }
    const next = { items: [{ id: 'a', thumb: url('a', 12, 'new') }] }
    const out = keepStableUrls(prev, next, NOW) as typeof next
    expect(out.items[0].thumb).toBe(prev.items[0].thumb)
  })

  it('takes the new URL once the old one is past half of its lifetime', () => {
    const prev = { items: [{ id: 'a', thumb: url('a', 0, 'old') }] }
    const next = { items: [{ id: 'a', thumb: url('a', 13, 'new') }] }
    const out = keepStableUrls(prev, next, Date.UTC(2026, 9, 22, 13, 0, 0) + 12 * 3600_000) as typeof next
    expect(out.items[0].thumb).toBe(next.items[0].thumb)
  })

  it('takes the new URL when the file changed', () => {
    const prev = { id: 'a', thumb: url('a', 11, 'old') }
    const next = { id: 'a', thumb: url('b', 12, 'new') }
    expect((keepStableUrls(prev, next, NOW) as typeof next).thumb).toBe(next.thumb)
  })

  it('matches array items by id even when the order changes', () => {
    const prev = { items: [{ id: 'a', u: url('a', 11, 'oa') }, { id: 'b', u: url('b', 11, 'ob') }] }
    const next = { items: [{ id: 'b', u: url('b', 12, 'nb') }, { id: 'a', u: url('a', 12, 'na') }] }
    const out = keepStableUrls(prev, next, NOW) as typeof next
    expect(out.items[0].u).toBe(prev.items[1].u)
    expect(out.items[1].u).toBe(prev.items[0].u)
  })

  it('leaves ordinary strings and unsigned URLs alone', () => {
    const next = { title: 'Новый', u: 'https://example.com/a.jpg' }
    expect(keepStableUrls({ title: 'Старый', u: 'https://example.com/b.jpg' }, next, NOW)).toEqual(next)
  })

  it('does not break pages of an infinite query (no ids, matched by index)', () => {
    const prev = { pages: [{ items: [{ id: 'a', u: url('a', 11, 'o') }] }], pageParams: [null] }
    const next = { pages: [{ items: [{ id: 'a', u: url('a', 12, 'n') }] }], pageParams: [null] }
    const out = keepStableUrls(prev, next, NOW) as typeof next
    expect(out.pages[0].items[0].u).toBe(prev.pages[0].items[0].u)
  })
})

describe('stableStructuralSharing', () => {
  it('returns the very same object when only signatures changed', () => {
    const prev = { items: [{ id: 'a', u: url('a', 11, 'old') }] }
    const next = { items: [{ id: 'a', u: url('a', 12, 'new') }] }
    // реальное время важно только для свежести: подставим «сейчас» через ссылки, выданные только что
    const fresh = (sig: string) => {
      const d = new Date()
      const p = (n: number) => String(n).padStart(2, '0')
      const stamp = `${d.getUTCFullYear()}${p(d.getUTCMonth() + 1)}${p(d.getUTCDate())}T${p(d.getUTCHours())}${p(d.getUTCMinutes())}${p(d.getUTCSeconds())}Z`
      return `https://impomento.pro/s3/im/a.webp?X-Amz-Date=${stamp}&X-Amz-Expires=86400&X-Amz-Signature=${sig}`
    }
    const a = { items: [{ id: 'a', u: fresh('one') }] }
    const b = { items: [{ id: 'a', u: fresh('two') }] }
    expect(stableStructuralSharing(a, b)).toBe(a)
    expect(stableStructuralSharing(undefined, next)).toBe(next)
    expect(prev).toBeTruthy()
  })
})
