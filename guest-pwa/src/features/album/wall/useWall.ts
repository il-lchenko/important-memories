import { useEffect, useState, type RefObject } from 'react'
import type { Frame } from '../AlbumScreen'

export const DESKTOP_BP = 1024

export function useIsDesktop(): boolean {
  const [v, setV] = useState(() => typeof window !== 'undefined' && window.matchMedia(`(min-width: ${DESKTOP_BP}px)`).matches)
  useEffect(() => {
    const m = window.matchMedia(`(min-width: ${DESKTOP_BP}px)`)
    const on = () => setV(m.matches)
    m.addEventListener('change', on)
    return () => m.removeEventListener('change', on)
  }, [])
  return v
}

/** Ширина элемента, обновляется при изменении размера окна и при открытии боковых панелей. */
export function useElementWidth(ref: RefObject<HTMLElement | null>): number {
  const [w, setW] = useState(0)
  useEffect(() => {
    const el = ref.current
    if (!el) return
    const update = () => setW(Math.floor(el.getBoundingClientRect().width))
    update()
    const ro = new ResizeObserver(update)
    ro.observe(el)
    return () => ro.disconnect()
  }, [ref])
  return w
}

export function hash32(s: string): number {
  let h = 2166136261
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i)
    h = Math.imul(h, 16777619)
  }
  return h >>> 0
}

/** Детерминированный генератор: один и тот же seed всегда даёт одну и ту же последовательность. */
export function rng(seed: number): () => number {
  let a = seed >>> 0
  return () => {
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), a | 1)
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

/** Пропорции кадра с учётом поворота; ограничены, чтобы стена не ломалась на панорамах. */
export function aspectOf(f: Frame): number {
  const w = f.width > 0 ? f.width : 3
  const h = f.height > 0 ? f.height : 4
  const rot = ((f.rotation ?? 0) % 360 + 360) % 360
  const a = rot % 180 === 0 ? w / h : h / w
  return Math.min(1.9, Math.max(0.55, a))
}

export interface Tile { i: number; w: number; h: number }
export interface Row { tiles: Tile[]; h: number; last: boolean }

/**
 * Раскладка «рядами одинаковой высоты»: кадры набираются в ряд, пока он не заполнит ширину,
 * затем ряд растягивается ровно до краёв. Последний ряд не растягивается, поэтому при подгрузке
 * новых кадров уже построенные ряды остаются на месте.
 */
export function justifyRows(frames: Frame[], width: number, gap: number, targetFor: (row: number) => number): Row[] {
  const rows: Row[] = []
  if (width <= 0) return rows
  let acc: { i: number; a: number }[] = []
  let sumA = 0
  const flush = (last: boolean) => {
    const target = targetFor(rows.length)
    const gaps = gap * (acc.length - 1)
    const h = last ? target : (width - gaps) / sumA
    const tiles = acc.map((t) => ({ i: t.i, w: t.a * h, h }))
    rows.push({ tiles, h, last })
    acc = []
    sumA = 0
  }
  for (let i = 0; i < frames.length; i++) {
    const a = aspectOf(frames[i])
    acc.push({ i, a })
    sumA += a
    const target = targetFor(rows.length)
    if (sumA * target + gap * (acc.length - 1) >= width) flush(false)
  }
  if (acc.length) flush(true)
  return rows
}
