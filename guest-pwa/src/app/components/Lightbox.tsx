import { useEffect, useState } from 'react'
import { ZoomPan } from '../../features/album/ZoomPan'
import { Icon, icons } from '../ui'

export interface LightboxFrame {
  id: string
  preview: string | null
  full: string
  rotation: number
  caption?: string | null
  subtitle?: string
}

/** Полноэкранный просмотр кадров с увеличением; при приближении подгружается оригинал. */
export function Lightbox({ frames, index, onIndex, onClose, onRemove }: {
  frames: LightboxFrame[]
  index: number
  onIndex: (i: number) => void
  onClose: () => void
  onRemove?: (frame: LightboxFrame) => void
}) {
  const frame = frames[index]
  const [fullLoaded, setFullLoaded] = useState<string | null>(null)

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
      if (e.key === 'ArrowRight' && index < frames.length - 1) onIndex(index + 1)
      if (e.key === 'ArrowLeft' && index > 0) onIndex(index - 1)
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [index, frames.length, onIndex, onClose])

  if (!frame) return null
  const barBtn = {
    width: 40, height: 40, border: '1px solid rgba(240,230,210,.5)', background: 'transparent',
    color: '#F0E6D2', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', borderRadius: 2,
  } as const
  const sideways = frame.rotation % 180 !== 0
  const imgStyle = {
    position: 'absolute' as const, inset: 0, width: '100%', height: '100%', objectFit: 'contain' as const,
    transform: frame.rotation ? `rotate(${frame.rotation}deg)${sideways ? ' scale(.56)' : ''}` : undefined,
  }

  return (
    <div className="darkroom" role="dialog" aria-modal="true" style={{ position: 'fixed', inset: 0, zIndex: 70, display: 'flex', flexDirection: 'column' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: 'calc(10px + env(safe-area-inset-top)) 12px 8px' }}>
        <button style={barBtn} aria-label="Закрыть" onClick={onClose}><Icon d={icons.close} /></button>
        <div style={{ flex: 1, textAlign: 'center', fontSize: 12, letterSpacing: '.14em', color: 'rgba(240,230,210,.6)' }}>
          {index + 1} / {frames.length}
        </div>
        <a style={{ ...barBtn, textDecoration: 'none' }} aria-label="Скачать оригинал" href={frame.full} target="_blank" rel="noreferrer" download><Icon d={icons.download} /></a>
        {onRemove && <button style={barBtn} aria-label="Убрать" onClick={() => onRemove(frame)}><Icon d={icons.trash} /></button>}
      </div>

      <div style={{ flex: 1, minHeight: 0, position: 'relative', padding: '0 8px' }}>
        <ZoomPan key={frame.id}>
          {(zoomed) => (
            <div style={{ position: 'absolute', inset: 0 }}>
              <img src={frame.preview ?? frame.full} alt="" draggable={false} style={imgStyle} />
              {zoomed && (
                <img src={frame.full} alt="" draggable={false} onLoad={() => setFullLoaded(frame.id)}
                  style={{ ...imgStyle, opacity: fullLoaded === frame.id ? 1 : 0, transition: 'opacity .2s ease' }} />
              )}
            </div>
          )}
        </ZoomPan>
        {index > 0 && <button style={{ ...barBtn, position: 'absolute', left: 12, top: '50%' }} aria-label="Предыдущий" onClick={() => onIndex(index - 1)}><Icon d={icons.back} /></button>}
        {index < frames.length - 1 && <button style={{ ...barBtn, position: 'absolute', right: 12, top: '50%' }} aria-label="Следующий" onClick={() => onIndex(index + 1)}><Icon d={icons.chevron} /></button>}
      </div>

      <div style={{ padding: '10px 20px calc(16px + env(safe-area-inset-bottom))', textAlign: 'center', minHeight: 56 }}>
        {frame.caption && <div style={{ fontFamily: 'Caveat, cursive', fontSize: 26 }}>{frame.caption}</div>}
        {frame.subtitle && <div style={{ fontSize: 13, color: 'rgba(240,230,210,.6)' }}>{frame.subtitle}</div>}
      </div>
    </div>
  )
}
