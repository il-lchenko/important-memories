import { useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import ReportModal from './ReportModal'

interface Frame {
  id: string
  guest_id: string
  guest_name: string
  captured_at: string
  thumbnail_url: string | null
  full_url: string
  width: number
  height: number
  is_mine: boolean
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('ru', { hour: '2-digit', minute: '2-digit' })
}

function IcBtn({ onClick, children }: { onClick?: () => void; children: React.ReactNode }) {
  return (
    <button
      onClick={onClick}
      style={{
        width: 36, height: 36, borderRadius: 18,
        background: 'rgba(255,255,255,.08)', color: 'var(--dr-text)',
        border: 'none', cursor: 'pointer',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        backdropFilter: 'blur(8px)',
      }}
    >
      {children}
    </button>
  )
}

export default function FrameFullscreen() {
  const { shortCode, frameIndex } = useParams<{ shortCode: string; frameIndex: string }>()
  const navigate = useNavigate()
  const { state } = useLocation() as { state: { frames: Frame[]; totalFrames: number } | null }
  const [showReport, setShowReport] = useState(false)

  const frames: Frame[] = state?.frames ?? []
  const totalFrames: number = state?.totalFrames ?? frames.length
  const index = parseInt(frameIndex ?? '0', 10)
  const frame = frames[index] ?? null

  const back = () => navigate(`/g/${shortCode}/album`)

  const handleShare = async () => {
    if (!frame) return
    const url = frame.full_url
    if (navigator.share) {
      try { await navigator.share({ url }) } catch {}
    } else {
      await navigator.clipboard.writeText(url).catch(() => {})
    }
  }

  const handleSave = () => {
    if (!frame) return
    const a = document.createElement('a')
    a.href = frame.full_url
    a.download = `frame-${index + 1}.jpg`
    a.target = '_blank'
    a.rel = 'noopener'
    a.click()
  }

  if (!frame) {
    return (
      <div style={{
        minHeight: '100dvh', background: 'var(--dark)',
        display: 'flex', flexDirection: 'column',
        alignItems: 'center', justifyContent: 'center', gap: 16,
      }}>
        <p style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontSize: 20, color: 'var(--dr-text)' }}>
          Кадр не найден
        </p>
        <button className="btn-ghost-dark btn-sm" onClick={back} style={{ padding: '0 24px', width: 'auto' }}>
          К альбому
        </button>
      </div>
    )
  }

  return (
    <div style={{ height: '100dvh', background: 'var(--dark)', display: 'flex', flexDirection: 'column' }}>
      {/* Top bar */}
      <div style={{
        paddingTop: 54, paddingLeft: 16, paddingRight: 16, paddingBottom: 12,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        flexShrink: 0,
      }}>
        <IcBtn onClick={back}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="6" y1="6" x2="18" y2="18" /><line x1="18" y1="6" x2="6" y2="18" />
          </svg>
        </IcBtn>

        <span style={{
          fontFamily: 'JetBrains Mono, monospace', fontSize: 11,
          letterSpacing: '.14em', color: 'rgba(240,230,210,.65)',
        }}>
          КАДР {index + 1} / {totalFrames}
        </span>

        <IcBtn onClick={() => setShowReport(true)}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <circle cx="12" cy="12" r="1.5" fill="currentColor" /><circle cx="6" cy="12" r="1.5" fill="currentColor" /><circle cx="18" cy="12" r="1.5" fill="currentColor" />
          </svg>
        </IcBtn>
      </div>

      {/* Photo — fills remaining space, contain to show full image in any ratio */}
      <div style={{ flex: 1, position: 'relative', overflow: 'hidden', minHeight: 0 }}>
        <img
          src={frame.full_url}
          alt=""
          style={{
            position: 'absolute', inset: 0,
            width: '100%', height: '100%',
            objectFit: 'contain', display: 'block',
          }}
        />

        {/* Overlay: guest name + time — pinned to bottom of photo area */}
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0,
          padding: '48px 18px 16px',
          background: 'linear-gradient(transparent, rgba(0,0,0,0.55))',
          display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        }}>
          <span style={{
            fontFamily: 'Caveat, cursive', fontSize: 28,
            color: 'rgba(246,242,232,.95)',
            textShadow: '0 1px 3px rgba(0,0,0,.55)',
          }}>
            {frame.guest_name}
          </span>
          <span style={{
            fontFamily: 'JetBrains Mono, monospace', fontSize: 11,
            color: 'rgba(255,179,71,.85)', letterSpacing: '.1em',
          }}>
            {formatTime(frame.captured_at)}
          </span>
        </div>
      </div>

      {/* Actions */}
      <div style={{
        flexShrink: 0,
        padding: '14px 20px 30px',
        display: 'flex', justifyContent: 'space-around',
        background: 'var(--dark)',
      }}>
        {/* Share */}
        <button onClick={handleShare} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--dr-text)', fontSize: 11, fontFamily: 'Inter, sans-serif' }}>
          <div style={{ width: 44, height: 44, borderRadius: 14, background: 'rgba(255,255,255,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(8px)' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8" /><polyline points="16 6 12 2 8 6" /><line x1="12" y1="2" x2="12" y2="15" />
            </svg>
          </div>
          <span>Поделиться</span>
        </button>

        {/* Save */}
        <button onClick={handleSave} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--dr-text)', fontSize: 11, fontFamily: 'Inter, sans-serif' }}>
          <div style={{ width: 44, height: 44, borderRadius: 14, background: 'rgba(255,255,255,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(8px)' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M12 4v12" /><polyline points="6 12 12 18 18 12" /><line x1="4" y1="21" x2="20" y2="21" />
            </svg>
          </div>
          <span>Сохранить</span>
        </button>

        {/* Report */}
        <button onClick={() => setShowReport(true)} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--dr-text)', fontSize: 11, fontFamily: 'Inter, sans-serif' }}>
          <div style={{ width: 44, height: 44, borderRadius: 14, background: 'rgba(255,255,255,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(8px)', color: 'var(--shutter)' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="9" /><line x1="12" y1="8" x2="12" y2="13" /><circle cx="12" cy="16.5" r=".5" fill="currentColor" />
            </svg>
          </div>
          <span>Жалоба</span>
        </button>
      </div>

      {showReport && (
        <ReportModal frameId={frame.id} onClose={() => setShowReport(false)} />
      )}
    </div>
  )
}

