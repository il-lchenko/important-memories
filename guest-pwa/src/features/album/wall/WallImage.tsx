import { useState } from 'react'
import type { Frame } from '../AlbumScreen'

/**
 * Фото в рамке известного размера w×h. Источник выбирается по реальному размеру на экране:
 * для крупных плиток берётся превью, для мелких миниатюра; если ссылка не открылась, идём дальше по цепочке.
 */
export function WallImage({ frame, w, h, index = 0 }: { frame: Frame; w: number; h: number; index?: number }) {
  const [step, setStep] = useState(0)
  const dpr = typeof window !== 'undefined' ? Math.min(2, window.devicePixelRatio || 1) : 1
  const big = Math.max(w, h) * dpr > 700
  const chain = (big
    ? [frame.preview_url, frame.thumbnail_url, frame.full_url]
    : [frame.thumbnail_url, frame.preview_url, frame.full_url]
  ).filter((u): u is string => !!u)
  const url = chain[Math.min(step, chain.length - 1)]
  const rot = ((frame.rotation ?? 0) % 360 + 360) % 360
  const sideways = rot % 180 !== 0

  if (!url) {
    const hue = (index * 37) % 360
    return <div style={{ width: '100%', height: '100%', background: `linear-gradient(135deg, hsl(${hue} 40% 60%), hsl(${hue} 45% 28%))` }} />
  }
  const common = { alt: '', loading: 'lazy' as const, decoding: 'async' as const, draggable: false, onError: () => setStep((s) => s + 1) }
  if (sideways) {
    return (
      <img key={url} src={url} {...common}
        style={{
          position: 'absolute', top: '50%', left: '50%', width: h, height: w, objectFit: 'cover',
          transform: `translate(-50%, -50%) rotate(${rot}deg)`, display: 'block', userSelect: 'none',
        }} />
    )
  }
  return (
    <img key={url} src={url} {...common}
      style={{
        width: '100%', height: '100%', objectFit: 'cover', display: 'block', userSelect: 'none',
        transform: rot ? `rotate(${rot}deg)` : undefined,
      }} />
  )
}
