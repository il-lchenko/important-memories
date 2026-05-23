import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useCamera } from '../../hooks/useCamera'
import { useNetworkStatus } from '../../hooks/useNetworkStatus'
import { guestApi } from '../../api/client'

interface QueueItem { blob: Blob; width: number; height: number; capturedAt: string }

function getEventMeta() {
  try { return JSON.parse(sessionStorage.getItem('event') ?? '{}') } catch { return {} }
}

// ── Icon helpers ─────────────────────────────────────────────────────────────
const ICFlash = () => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <polygon points="13 2 4 14 11 14 9 22 20 10 13 10 13 2"/>
  </svg>
)
const ICFlip = () => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M3 8a8 8 0 0 1 13.7-5.7L19 4"/><polyline points="19 1 19 5 15 5"/>
    <path d="M21 16a8 8 0 0 1-13.7 5.7L5 20"/><polyline points="5 23 5 19 9 19"/>
  </svg>
)

const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent)

// ── Frame preview overlay (after shutter) ────────────────────────────────────
function FramePreview({ blobUrl, frameNum, onShootMore, onAlbum }: {
  blobUrl: string; frameNum: number; onShootMore: () => void; onAlbum: () => void;
}) {
  const [savedHint, setSavedHint] = useState(false)

  const handleSave = () => {
    const a = document.createElement('a')
    a.href = blobUrl
    a.download = `kdr-${frameNum}.jpg`
    a.click()
    if (isIOS) {
      setSavedHint(true)
      setTimeout(() => setSavedHint(false), 2500)
    }
  }

  return (
    <div className="darkroom" style={{ position: 'absolute', inset: 0, zIndex: 50, display: 'flex', flexDirection: 'column' }}>
      {/* Save icon — top right */}
      <div style={{ position: 'absolute', top: 14, right: 16, zIndex: 10, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
        <button
          onClick={handleSave}
          aria-label="Сохранить фото"
          style={{
            width: 36, height: 36, borderRadius: 18,
            background: 'rgba(255,255,255,.1)', border: 'none',
            color: 'rgba(240,230,210,.7)', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            backdropFilter: 'blur(8px)',
          }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 4v12"/><polyline points="6 12 12 18 18 12"/><line x1="4" y1="21" x2="20" y2="21"/>
          </svg>
        </button>
        {savedHint && (
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.1em', color: 'rgba(240,230,210,.55)', whiteSpace: 'nowrap' }}>
            → Файлы
          </span>
        )}
      </div>

      <div style={{ padding: '12px 24px 24px', fontFamily: 'JetBrains Mono, monospace', fontSize: 11, color: 'rgba(240,230,210,.55)', letterSpacing: '.14em', textAlign: 'center', textTransform: 'uppercase', paddingTop: 80 }}>
        КАДР {frameNum} · ИЗ ПРОЯВКИ НЕ УБРАТЬ
      </div>

      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '12px 0', flex: 1 }}>
        <div style={{
          width: 270, padding: '16px 16px 0',
          background: 'var(--paper)', borderRadius: 4,
          transform: 'rotate(-1.5deg)',
          boxShadow: '0 20px 50px -8px rgba(0,0,0,.5), 0 0 80px -10px rgba(255,179,71,.15)',
        }}>
          <div style={{ aspectRatio: '1', borderRadius: 2, overflow: 'hidden', position: 'relative' }}>
            <img src={blobUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div>
          <div style={{ height: 56, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontFamily: 'Caveat, cursive', fontSize: 26, color: 'var(--ink-2)' }}>
              {sessionStorage.getItem('guest_name') ?? 'Гость'}
            </span>
          </div>
        </div>
      </div>

      <div style={{ padding: '20px 28px', fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 400, fontSize: 18, lineHeight: 1.4, color: 'var(--dr-text)', textAlign: 'center' }}>
        Снимок не отменить, как и сам момент.
      </div>

      <div className="footer-gradient dark" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <button className="btn-dark-amber" onClick={onShootMore}>
          Снять ещё
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--dark)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="13 6 19 12 13 18"/></svg>
        </button>
        <button className="btn-ghost-dark btn-sm" onClick={onAlbum}>К альбому</button>
      </div>
    </div>
  )
}

// ── Offline screen ───────────────────────────────────────────────────────────
function OfflineScreen({ queue, onRetry, onContinue }: {
  queue: QueueItem[]; onRetry: () => void; onContinue: () => void;
}) {
  const thumbUrls = queue.map((q) => URL.createObjectURL(q.blob))
  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column', paddingTop: 60 }}>
      <div style={{ padding: '14px 24px 0' }}>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, letterSpacing: '.14em', color: 'var(--shutter)', textTransform: 'uppercase', display: 'inline-flex', alignItems: 'center', gap: 6 }}>
          <span style={{ width: 6, height: 6, borderRadius: '50%', background: 'var(--shutter)', display: 'inline-block' }} />
          Связь потеряна
        </div>
        <h1 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 28, lineHeight: 1.05, letterSpacing: '-.02em', margin: '6px 0 2px' }}>
          Не торопитесь —<br />кадры в кармане.
        </h1>
      </div>

      <div style={{ padding: '14px 24px 24px' }}>
        {/* Off card */}
        <div style={{ borderRadius: 20, background: 'var(--paper-2)', padding: '18px 18px 14px', borderLeft: '3px solid var(--amber)', marginTop: 4 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 6 }}>
            <div style={{ width: 32, height: 32, borderRadius: '50%', background: 'rgba(201,136,30,.15)', color: 'var(--amber)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M2 8.8a16 16 0 0 1 20 0"/><path d="M5 12a11 11 0 0 1 14 0"/>
                <path d="M8.5 15.5a6 6 0 0 1 7 0"/><circle cx="12" cy="19" r="1.5" fill="currentColor"/>
                <line x1="3" y1="3" x2="21" y2="21" stroke="var(--shutter)"/>
              </svg>
            </div>
            <h3 style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 19, letterSpacing: '-.01em' }}>Wi-Fi уехал</h3>
          </div>
          <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-3)', lineHeight: 1.5 }}>
            Снимайте дальше — кадры отправятся, как только связь вернётся.
          </p>
        </div>

        {/* Pending queue */}
        {queue.length > 0 && (
          <div style={{ marginTop: 16, padding: 14, borderRadius: 16, background: 'var(--paper-2)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 10 }}>
              <h4 style={{ fontFamily: 'Inter, sans-serif', fontSize: 13, fontWeight: 600 }}>В очереди</h4>
              <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 11, color: 'var(--amber)', letterSpacing: '.08em' }}>{queue.length} · ОТПРАВКА…</span>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr 1fr', gap: 6 }}>
              {thumbUrls.slice(0, 3).map((url, i) => (
                <div key={i} style={{ aspectRatio: '1', borderRadius: 6, position: 'relative', overflow: 'hidden', background: 'var(--dark-2)' }}>
                  <img src={url} alt="" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover', opacity: 0.55 }} />
                  <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                    <div style={{ width: 22, height: 22, borderRadius: '50%', border: '2px solid rgba(246,242,232,.3)', borderTopColor: 'var(--dr-amber)', animation: 'spin 1.2s linear infinite', animationDelay: `${-i * 0.4}s` }} />
                  </div>
                </div>
              ))}
            </div>
          </div>
        )}

        <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column', gap: 8 }}>
          <button className="btn" onClick={onRetry}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><polyline points="3 8 8 8 8 3"/><path d="M3 8a9 9 0 0 1 15 0"/><polyline points="21 16 16 16 16 21"/><path d="M21 16a9 9 0 0 1-15 0"/></svg>
            Попробовать сейчас
          </button>
          <button className="btn-ghost btn-sm" onClick={onContinue}>Продолжить снимать</button>
        </div>
        <div style={{ textAlign: 'center', fontSize: 12, color: 'var(--ink-3)', marginTop: 12 }}>Кадры хранятся локально до отправки.</div>
      </div>
      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  )
}

// ── Main CameraScreen ────────────────────────────────────────────────────────
export default function CameraScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const { videoRef, ready, error, start, capture } = useCamera()
  const online = useNetworkStatus()
  const [facingMode, setFacingMode] = useState<'environment' | 'user'>('environment')
  const [shooting, setShooting] = useState(false)
  const [framesLeft, setFramesLeft] = useState<number | null>(null)
  const [framesTotal, setFramesTotal] = useState<number | null>(null)
  const [revealTime, setRevealTime] = useState<string | null>(null)
  const [retrying, setRetrying] = useState(false)
  const [showOffline, setShowOffline] = useState(false)
  const [preview, setPreview] = useState<{ url: string; frameNum: number } | null>(null)
  const uploadQueue = useRef<QueueItem[]>([])
  const guestName = sessionStorage.getItem('guest_name') ?? 'Гость'

  const event = getEventMeta()
  const photoFormat: string = event.settings?.photo_format ?? 'portrait_34'
  const captureRatio = photoFormat === 'landscape_43' ? 4 / 3 : 3 / 4

  useEffect(() => {
    setRevealTime(event.settings?.reveal_at ?? null)
    guestApi.getSession().then(({ data }) => {
      setFramesLeft(data.frames_remaining)
      setFramesTotal(data.event.settings.frames_per_guest)
    }).catch(() => {})
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => { start(facingMode, captureRatio) }, [facingMode]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    if (online && uploadQueue.current.length > 0) processQueue()
  }, [online]) // eslint-disable-line react-hooks/exhaustive-deps

  const uploadItem = useCallback(async (item: QueueItem): Promise<boolean> => {
    try {
      const { data: presign } = await guestApi.presign(item.blob.size)
      await fetch(presign.upload_url, { method: 'PUT', body: item.blob, headers: { 'Content-Type': 'image/jpeg' } })
      const { data: reg } = await guestApi.registerFrame(presign.frame_id, item.capturedAt, item.width, item.height)
      setFramesLeft(reg.frames_remaining)
      if (reg.frames_remaining === 0) navigate(`/g/${shortCode}/done`)
      return true
    } catch { return false }
  }, [shortCode, navigate])

  const processQueue = async () => {
    if (retrying) return
    setRetrying(true)
    for (const item of [...uploadQueue.current]) {
      const ok = await uploadItem(item)
      if (ok) uploadQueue.current = uploadQueue.current.filter((q) => q !== item)
      else break
    }
    setRetrying(false)
  }

  const handleShutter = async () => {
    if (shooting) return
    setShooting(true)
    try {
      const shot = await capture(captureRatio)
      if (!shot) return
      setFramesLeft((n) => (n !== null ? Math.max(0, n - 1) : null))
      const capturedAt = new Date().toISOString()
      const blobUrl = URL.createObjectURL(shot.blob)
      const frameNum = framesTotal != null && framesLeft != null ? framesTotal - framesLeft + 1 : 1
      const ok = await uploadItem({ blob: shot.blob, width: shot.width, height: shot.height, capturedAt })
      if (!ok) uploadQueue.current.push({ blob: shot.blob, width: shot.width, height: shot.height, capturedAt })
      setPreview({ url: blobUrl, frameNum })
    } finally {
      setShooting(false)
    }
  }

  const revealLabel = revealTime
    ? new Date(revealTime).toLocaleTimeString('ru', { hour: '2-digit', minute: '2-digit' })
    : null

  // Offline full-screen mode
  if (!online && showOffline) {
    return <OfflineScreen
      queue={uploadQueue.current}
      onRetry={() => { processQueue(); setShowOffline(false) }}
      onContinue={() => setShowOffline(false)}
    />
  }

  // Post-shutter preview
  if (preview) {
    return <FramePreview
      blobUrl={preview.url}
      frameNum={preview.frameNum}
      onShootMore={() => { setPreview(null); start(facingMode, captureRatio) }}
      onAlbum={() => navigate(`/g/${shortCode}/album`)}
    />
  }

  return (
    <div className="darkroom" style={{ position: 'relative', height: '100dvh', overflow: 'hidden', userSelect: 'none' }}>

      {/* ── Full-screen video ── */}
      {!error ? (
        <video ref={videoRef} playsInline muted style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />
      ) : (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 12, padding: 32, textAlign: 'center' }}>
          <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="rgba(240,230,210,.4)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <path d="M3 7h4l2-3h6l2 3h4v13H3z"/><circle cx="12" cy="13" r="4"/>
          </svg>
          <p style={{ margin: 0, fontSize: 15, color: 'var(--dr-text)' }}>Нет доступа к камере</p>
          <p style={{ margin: 0, fontSize: 13, color: 'rgba(240,230,210,.45)' }}>{error}</p>
        </div>
      )}

      {/* ── Vignette ── */}
      <div style={{ position: 'absolute', inset: 0, background: 'radial-gradient(ellipse at center, transparent 45%, rgba(0,0,0,.45) 100%)', pointerEvents: 'none' }} />

      {/* ── Film corner marks ── */}
      {([['tl', 'top', 'left'], ['tr', 'top', 'right'], ['bl', 'bottom', 'left'], ['br', 'bottom', 'right']] as const).map(([id, v, h]) => (
        <div key={id} style={{
          position: 'absolute',
          [v]: v === 'top' ? 62 : 195,
          [h]: 14,
          width: 22, height: 22, color: 'var(--dr-amber)', pointerEvents: 'none',
          borderTop: v === 'top' ? '1.5px solid' : 'none',
          borderBottom: v === 'bottom' ? '1.5px solid' : 'none',
          borderLeft: h === 'left' ? '1.5px solid' : 'none',
          borderRight: h === 'right' ? '1.5px solid' : 'none',
          borderTopLeftRadius: id === 'tl' ? 4 : 0,
          borderTopRightRadius: id === 'tr' ? 4 : 0,
          borderBottomLeftRadius: id === 'bl' ? 4 : 0,
          borderBottomRightRadius: id === 'br' ? 4 : 0,
        }} />
      ))}

      {/* ── Top overlay: banners + guest name/counter ── */}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, background: 'linear-gradient(180deg, rgba(22,16,12,.82) 0%, transparent 100%)', paddingBottom: 32 }}>
        {uploadQueue.current.length > 0 && online && (
          <div style={{ background: 'var(--shutter)', padding: '8px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontFamily: 'Inter, sans-serif', fontSize: 13, color: '#fff' }}>
            <span>{uploadQueue.current.length} кадр{uploadQueue.current.length > 1 ? 'а' : ''} в очереди</span>
            <button onClick={processQueue} disabled={retrying} style={{ background: 'rgba(255,255,255,.2)', border: 'none', color: '#fff', cursor: 'pointer', fontSize: 12, fontFamily: 'Inter, sans-serif', padding: '4px 10px', borderRadius: 6 }}>
              {retrying ? '...' : 'Повторить'}
            </button>
          </div>
        )}
        {!online && (
          <div onClick={() => setShowOffline(true)} style={{ background: 'var(--shutter)', padding: '8px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontFamily: 'Inter, sans-serif', fontSize: 13, color: '#fff', cursor: 'pointer' }}>
            <span>Нет сети — кадры сохранены</span>
            <span style={{ opacity: 0.8 }}>Подробнее →</span>
          </div>
        )}
        <div style={{ padding: '10px 24px 0', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 500, fontSize: 22, letterSpacing: '-.01em', color: 'var(--dr-text)' }}>
            {guestName}
          </div>
          {framesLeft !== null && framesTotal !== null && (
            <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 16, fontWeight: 500, color: 'var(--dr-amber)', letterSpacing: '.04em' }}>
              {framesLeft} <span style={{ opacity: 0.55 }}>/ {framesTotal}</span>
            </div>
          )}
        </div>
      </div>

      {/* ── Bottom overlay: film info + controls + meta ── */}
      <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, background: 'linear-gradient(0deg, rgba(22,16,12,.9) 0%, transparent 100%)', padding: '52px 24px 32px' }}>
        {/* Film info */}
        <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'JetBrains Mono, monospace', fontSize: 10, color: 'var(--dr-amber)', letterSpacing: '.12em', marginBottom: 16 }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ width: 5, height: 5, borderRadius: '50%', background: 'var(--shutter)', display: 'inline-block' }} />
            PORTRA 400
          </div>
          <span>ƒ 2.8</span>
        </div>

        {/* Controls */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 16 }}>
          {/* Flash (disabled) */}
          <div style={{ width: 52, height: 52, borderRadius: 26, background: 'rgba(255,179,71,.08)', border: '1px solid rgba(255,179,71,.2)', color: 'rgba(255,179,71,.3)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <ICFlash />
          </div>

          {/* Shutter */}
          <button
            onClick={handleShutter}
            disabled={!ready || shooting}
            style={{
              width: 76, height: 76, borderRadius: '50%',
              background: 'var(--dr-text)',
              border: '4px solid rgba(255,179,71,.25)',
              boxShadow: '0 0 0 2px var(--dark), 0 0 0 5px rgba(255,179,71,.35), 0 0 28px -2px rgba(255,179,71,.35)',
              cursor: ready ? 'pointer' : 'not-allowed',
              transition: 'transform 0.1s',
              transform: shooting ? 'scale(0.9)' : 'scale(1)',
              flexShrink: 0,
            }}
            aria-label="Снять фото"
          />

          {/* Flip */}
          <button
            onClick={() => setFacingMode((m) => m === 'environment' ? 'user' : 'environment')}
            style={{ width: 52, height: 52, borderRadius: 26, background: 'rgba(255,179,71,.08)', border: '1px solid rgba(255,179,71,.2)', color: 'var(--dr-amber)', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}
            aria-label="Переключить камеру"
          >
            <ICFlip />
          </button>
        </div>

        {/* Meta */}
        <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: 'JetBrains Mono, monospace', fontSize: 11, color: 'var(--dr-amber)', letterSpacing: '.14em' }}>
          <span>{framesLeft !== null ? `${framesLeft} ОСТАЛОСЬ` : ''}</span>
          {revealLabel && <span style={{ color: 'rgba(240,230,210,.45)' }}>ПРОЯВКА {revealLabel}</span>}
        </div>
      </div>
    </div>
  )
}
