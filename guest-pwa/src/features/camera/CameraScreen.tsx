import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useCamera } from '../../hooks/useCamera'
import { useNetworkStatus } from '../../hooks/useNetworkStatus'
import { guestApi } from '../../api/client'
import { preloadFilmLUT } from '../../utils/filmLut'

interface QueueItem { blob: Blob; width: number; height: number; capturedAt: string }

function getEventMeta() {
  try { return JSON.parse(sessionStorage.getItem('event') ?? '{}') } catch { return {} }
}

function _filmLabel(lut: string): string {
  const map: Record<string, string> = {
    portra400: 'PORTRA 400', fuji400h: 'FUJI 400H',
    cinestill: 'CINESTILL', ilford: 'ILFORD HP5+', original: 'БЕЗ ФИЛЬТРА',
  }
  return map[lut] ?? lut.toUpperCase()
}

function playShutterSound() {
  try {
    const AudioCtx = window.AudioContext || (window as unknown as { webkitAudioContext: typeof AudioContext }).webkitAudioContext
    const ctx = new AudioCtx()
    const sr = ctx.sampleRate
    const len = Math.floor(sr * 0.055)
    const buf = ctx.createBuffer(1, len, sr)
    const d = buf.getChannelData(0)
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 5.5)
    const src = ctx.createBufferSource()
    src.buffer = buf
    const f = ctx.createBiquadFilter()
    f.type = 'bandpass'
    f.frequency.value = 2600
    f.Q.value = 0.7
    const g = ctx.createGain()
    g.gain.setValueAtTime(0.58, ctx.currentTime)
    g.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.055)
    src.connect(f); f.connect(g); g.connect(ctx.destination)
    src.start(); src.stop(ctx.currentTime + 0.06)
  } catch { /* ignore */ }
}

// ── Icons ────────────────────────────────────────────────────────────────────
const ICFlash = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <polygon points="13 2 4 14 11 14 9 22 20 10 13 10 13 2"/>
  </svg>
)
const ICFlashOff = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <polygon points="13 2 4 14 11 14 9 22 20 10 13 10 13 2" opacity="0.5"/>
    <line x1="3" y1="3" x2="21" y2="21"/>
  </svg>
)
const ICFlip = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
    <path d="M3 8a8 8 0 0 1 13.7-5.7L19 4"/><polyline points="19 1 19 5 15 5"/>
    <path d="M21 16a8 8 0 0 1-13.7 5.7L5 20"/><polyline points="5 23 5 19 9 19"/>
  </svg>
)
const ICRotate = () => (
  <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
    <rect x="5" y="2" width="14" height="20" rx="2"/>
    <path d="M15 2.5A9 9 0 0 1 19.5 13"/>
    <polyline points="22 10 19.5 13 17 10"/>
  </svg>
)

const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent)

// ── Film strip counter ───────────────────────────────────────────────────────
function FilmCounter({ frames }: { frames: number }) {
  const Holes = () => (
    <div style={{ display: 'flex', flexDirection: 'column', justifyContent: 'space-between', alignSelf: 'stretch', padding: '5px 4px', background: 'rgba(0,0,0,0.45)', gap: 2 }}>
      {[0, 1, 2].map(i => (
        <div key={i} style={{ width: 6, height: 5, borderRadius: 1, background: 'rgba(255,255,255,0.2)' }} />
      ))}
    </div>
  )
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'stretch',
      background: 'rgba(0,0,0,0.45)', backdropFilter: 'blur(8px)', WebkitBackdropFilter: 'blur(8px)',
      borderRadius: 6, overflow: 'hidden', minHeight: 36, border: '1px solid rgba(255,179,71,.1)',
    }}>
      <Holes />
      <div style={{
        padding: '0 10px', display: 'flex', alignItems: 'center', justifyContent: 'center',
        fontFamily: 'JetBrains Mono, monospace', fontSize: 20, fontWeight: 700,
        color: '#FFB347', lineHeight: 1, letterSpacing: '-.02em',
      }}>
        {frames}
      </div>
      <Holes />
    </div>
  )
}

// ── FramePreview ─────────────────────────────────────────────────────────────
function FramePreview({ blobUrl, frameNum, onShootMore, onSign, captureRatio, uploadStatus, canSign }: {
  blobUrl: string; frameNum: number; onShootMore: () => void; onSign: () => Promise<void> | void;
  captureRatio: number; uploadStatus: 'pending' | 'ok' | 'failed'; canSign: boolean;
}) {
  const [savedHint, setSavedHint] = useState(false)
  const [signLoading, setSignLoading] = useState(false)

  const handleSignClick = async () => {
    setSignLoading(true)
    try { await onSign() } finally { setSignLoading(false) }
  }

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
      <div style={{ position: 'absolute', top: 14, right: 16, zIndex: 10, display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
        <button
          onClick={handleSave}
          aria-label="Сохранить фото"
          style={{ width: 36, height: 36, borderRadius: 18, background: 'rgba(255,255,255,.1)', border: 'none', color: 'rgba(240,230,210,.7)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(8px)' }}
        >
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
            <path d="M12 4v12"/><polyline points="6 12 12 18 18 12"/><line x1="4" y1="21" x2="20" y2="21"/>
          </svg>
        </button>
        {savedHint && (
          <span style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.1em', color: 'rgba(240,230,210,.55)', whiteSpace: 'nowrap' }}>→ Файлы</span>
        )}
      </div>

      <div style={{ padding: '8px 24px 0', fontFamily: 'JetBrains Mono, monospace', fontSize: 11, color: 'rgba(240,230,210,.55)', letterSpacing: '.14em', textAlign: 'center', paddingTop: 60 }}>
        КАДР {frameNum} · МОМЕНТ ЗАПЕЧАТЛЁН
      </div>

      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '10px 0', flex: 1, minHeight: 0 }}>
        <div style={{ width: captureRatio > 1 ? 300 : 240, padding: '14px 14px 0', background: 'var(--paper)', borderRadius: 4, transform: 'rotate(-1.5deg)', boxShadow: '0 20px 50px -8px rgba(0,0,0,.5), 0 0 80px -10px rgba(255,179,71,.15)', flexShrink: 0 }}>
          <div style={{ aspectRatio: captureRatio > 1 ? '4/3' : '3/4', borderRadius: 2, overflow: 'hidden', position: 'relative' }}>
            <img src={blobUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', transform: captureRatio > 1 ? 'rotate(180deg)' : 'none' }} />
          </div>
          <div style={{ height: 48, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <span style={{ fontFamily: 'Caveat, cursive', fontSize: 24, color: 'var(--ink-2)' }}>
              {sessionStorage.getItem('guest_name') ?? 'Гость'}
            </span>
          </div>
        </div>
      </div>

      <div style={{ padding: '10px 28px 6px', fontFamily: 'Fraunces, serif', fontStyle: 'italic', fontWeight: 400, fontSize: 16, lineHeight: 1.4, color: 'var(--dr-text)', textAlign: 'center' }}>
        Снимок не отменить, как и сам момент.
      </div>

      <div className="footer-gradient dark" style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <button className="btn-dark-amber" onClick={onShootMore}>
          Новый кадр
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--dark)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="13 6 19 12 13 18"/></svg>
        </button>
        {canSign && (
        <button className="btn-ghost-dark btn-sm" onClick={handleSignClick} disabled={signLoading || uploadStatus === 'failed'}>
          {signLoading || uploadStatus === 'pending' ? (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 8 }}>
              <span style={{ width: 12, height: 12, borderRadius: '50%', border: '1.5px solid rgba(240,230,210,.3)', borderTopColor: 'var(--dr-amber)', display: 'inline-block', animation: 'fp-spin 0.8s linear infinite' }} />
              Кадр загружается…
            </span>
          ) : (
            <>
              <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" style={{ marginRight: 6, verticalAlign: 'middle' }}>
                <path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/>
                <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/>
              </svg>
              Подписать кадр
            </>
          )}
        </button>
        )}
        {canSign && uploadStatus === 'failed' && (
          <div style={{ fontSize: 11, color: 'var(--shutter)', textAlign: 'center', fontFamily: 'Inter, sans-serif' }}>
            Кадр не загрузился — без интернета подписать нельзя
          </div>
        )}
      </div>
      <style>{`@keyframes fp-spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  )
}

// ── OfflineScreen ─────────────────────────────────────────────────────────────
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
          <p style={{ margin: 0, fontSize: 13, color: 'var(--ink-3)', lineHeight: 1.5 }}>Снимайте дальше — кадры отправятся, как только связь вернётся.</p>
        </div>
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

interface RecentShot { url: string; frameNum: number; ratio: number }

const RECENT_LIMIT = 3
const recentShotsKey = (shortCode: string | undefined) => `im_recent_${shortCode ?? 'x'}`

function loadRecentShots(shortCode: string | undefined): RecentShot[] {
  try {
    const raw = sessionStorage.getItem(recentShotsKey(shortCode))
    if (!raw) return []
    const parsed = JSON.parse(raw)
    if (!Array.isArray(parsed)) return []
    return parsed.filter((s) => s && typeof s.url === 'string').slice(0, RECENT_LIMIT)
  } catch { return [] }
}

function saveRecentShots(shortCode: string | undefined, shots: RecentShot[]): void {
  try {
    sessionStorage.setItem(recentShotsKey(shortCode), JSON.stringify(shots.slice(0, RECENT_LIMIT)))
  } catch { /* quota exceeded — skip */ }
}

async function blobToThumbDataUrl(blob: Blob, maxSize: number = 160): Promise<string> {
  const img = new Image()
  const url = URL.createObjectURL(blob)
  try {
    await new Promise<void>((resolve, reject) => {
      img.onload = () => resolve()
      img.onerror = () => reject(new Error('image load failed'))
      img.src = url
    })
    const ratio = img.width / img.height
    const w = ratio >= 1 ? maxSize : Math.round(maxSize * ratio)
    const h = ratio >= 1 ? Math.round(maxSize / ratio) : maxSize
    const canvas = document.createElement('canvas')
    canvas.width = w; canvas.height = h
    const ctx = canvas.getContext('2d')!
    ctx.drawImage(img, 0, 0, w, h)
    return canvas.toDataURL('image/jpeg', 0.7)
  } finally {
    URL.revokeObjectURL(url)
  }
}

// ── Recent shots stack ───────────────────────────────────────────────────────
function RecentStack({ shots, onOpen }: { shots: RecentShot[]; onOpen: (s: RecentShot) => void }) {
  return (
    <div style={{ position: 'relative', width: 80, height: 66 }}>
      {[2, 1, 0].map((slot) => {
        const shot = shots[slot]
        const rotations = [2, -4, 6]
        const offsets = [{ x: 24, y: 10 }, { x: 12, y: 5 }, { x: 0, y: 0 }]
        const isTop = slot === 0
        return (
          <button
            key={slot}
            type="button"
            onClick={shot ? () => onOpen(shot) : undefined}
            disabled={!shot}
            aria-label={shot ? `Открыть кадр ${shot.frameNum}` : undefined}
            style={{
              position: 'absolute',
              right: offsets[slot].x, top: offsets[slot].y,
              width: 50, padding: 3,
              background: shot ? '#f5ead0' : 'rgba(245,234,208,.15)',
              border: 'none', borderRadius: 2,
              transform: `rotate(${rotations[slot]}deg)`,
              boxShadow: shot ? '0 4px 10px rgba(0,0,0,.5)' : 'none',
              zIndex: 3 - slot,
              cursor: shot && isTop ? 'pointer' : 'default',
              pointerEvents: shot && isTop ? 'auto' : 'none',
            }}
          >
            <div style={{ aspectRatio: '1', background: shot ? '#000' : 'rgba(255,179,71,.06)', overflow: 'hidden', borderRadius: 1 }}>
              {shot && <img src={shot.url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />}
            </div>
          </button>
        )
      })}
    </div>
  )
}

// ── Main CameraScreen ────────────────────────────────────────────────────────
export default function CameraScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const { videoRef, ready, error, start, capture, torchSupported, torchOn, setTorch } = useCamera()
  const online = useNetworkStatus()
  const [facingMode, setFacingMode] = useState<'environment' | 'user'>('environment')
  const [shooting, setShooting] = useState(false)
  const [framesLeft, setFramesLeft] = useState<number | null>(null)
  const [framesTotal, setFramesTotal] = useState<number | null>(null)
  const [retrying, setRetrying] = useState(false)
  const [showOffline, setShowOffline] = useState(false)
  const [preview, setPreview] = useState<{
    url: string; frameNum: number; ratio: number;
    frameId: string | null; uploadStatus: 'pending' | 'ok' | 'failed';
    canSign: boolean;
  } | null>(null)
  const uploadPromiseRef = useRef<Promise<{ ok: true; frameId: string } | { ok: false }> | null>(null)
  const [flashOn, setFlashOn] = useState(false)
  const [screenFlashing, setScreenFlashing] = useState(false)
  const [recentShots, setRecentShots] = useState<RecentShot[]>(() => loadRecentShots(shortCode))
  const [isLandscape, setIsLandscape] = useState(() => window.matchMedia('(orientation: landscape)').matches)
  const [streamRatio, setStreamRatio] = useState<number>(4 / 3)
  const uploadQueue = useRef<QueueItem[]>([])

  const event = getEventMeta()
  const lutPreset: string = event.settings?.lut_preset ?? 'portra400'
  const lutLabel = _filmLabel(lutPreset)

  useEffect(() => {
    guestApi.getSession().then(({ data }) => {
      const remaining = data.frames_remaining
      setFramesLeft(remaining)
      setFramesTotal(data.event.settings.frames_per_guest)
      if (remaining === 0) navigate(`/g/${shortCode}/done`, { replace: true })
    }).catch(() => {})
    preloadFilmLUT(lutPreset)
  }, []) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => { start(facingMode) }, [facingMode]) // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    const mq = window.matchMedia('(orientation: landscape)')
    const onChange = (e: MediaQueryListEvent) => setIsLandscape(e.matches)
    mq.addEventListener('change', onChange)

    let accelTimer: ReturnType<typeof setTimeout>
    const onOrientation = (e: DeviceOrientationEvent) => {
      if (e.gamma === null) return
      clearTimeout(accelTimer)
      accelTimer = setTimeout(() => setIsLandscape(Math.abs(e.gamma!) > 50), 150)
    }
    window.addEventListener('deviceorientation', onOrientation)

    return () => {
      mq.removeEventListener('change', onChange)
      window.removeEventListener('deviceorientation', onOrientation)
      clearTimeout(accelTimer)
    }
  }, [])

  useEffect(() => {
    if (ready && torchSupported && flashOn !== torchOn) setTorch(flashOn)
  }, [ready, torchSupported, flashOn, torchOn, setTorch])

  useEffect(() => {
    if (online && uploadQueue.current.length > 0) processQueue()
  }, [online]) // eslint-disable-line react-hooks/exhaustive-deps

  // recentShots are stored as data: URLs in sessionStorage — no blob URLs to revoke.

  const uploadItem = useCallback(async (item: QueueItem): Promise<{ ok: true; frameId: string } | { ok: false }> => {
    try {
      const { data: presign } = await guestApi.presign(item.blob.size)
      const putRes = await fetch(presign.upload_url, { method: 'PUT', body: item.blob, headers: { 'Content-Type': 'image/jpeg' } })
      if (!putRes.ok) throw new Error(`S3 upload failed: ${putRes.status}`)
      const { data: reg } = await guestApi.registerFrame(presign.frame_id, item.capturedAt, item.width, item.height)
      setFramesLeft(reg.frames_remaining)
      if (reg.frames_remaining === 0) navigate(`/g/${shortCode}/done`)
      return { ok: true, frameId: presign.frame_id }
    } catch { return { ok: false } }
  }, [shortCode, navigate])

  const processQueue = async () => {
    if (retrying) return
    setRetrying(true)
    for (const item of [...uploadQueue.current]) {
      const res = await uploadItem(item)
      if (res.ok) uploadQueue.current = uploadQueue.current.filter((q) => q !== item)
      else break
    }
    setRetrying(false)
  }

  const handleShutter = async () => {
    if (shooting) return
    setShooting(true)
    try {
      if (flashOn && !torchSupported) {
        setScreenFlashing(true)
        await new Promise((r) => setTimeout(r, 180))
      }
      playShutterSound()
      const actualRatio = isLandscape ? 4 / 3 : 3 / 4
      const shot = await capture(actualRatio, facingMode === 'user', lutPreset)
      if (flashOn && !torchSupported) setScreenFlashing(false)
      if (!shot) return
      setFramesLeft((n) => (n !== null ? Math.max(0, n - 1) : null))
      const capturedAt = new Date().toISOString()
      const blobUrl = URL.createObjectURL(shot.blob)
      const frameNum = framesTotal != null && framesLeft != null ? framesTotal - framesLeft + 1 : 1
      const thumbDataUrl = await blobToThumbDataUrl(shot.blob).catch(() => blobUrl)
      setRecentShots((prev) => {
        const next: RecentShot[] = [
          { url: thumbDataUrl, frameNum, ratio: actualRatio },
          ...prev,
        ].slice(0, RECENT_LIMIT)
        saveRecentShots(shortCode, next)
        return next
      })
      // Запускаем upload в фоне — preview показываем сразу, чтобы можно было сразу подписать
      const item: QueueItem = { blob: shot.blob, width: shot.width, height: shot.height, capturedAt }
      const promise = uploadItem(item)
      uploadPromiseRef.current = promise
      setPreview({ url: blobUrl, frameNum, ratio: actualRatio, frameId: null, uploadStatus: 'pending', canSign: true })
      // Обновляем preview когда upload завершится — но только если preview всё ещё этот же
      promise.then((res) => {
        if (!res.ok) uploadQueue.current.push(item)
        setPreview((curr) => {
          if (!curr || curr.url !== blobUrl) return curr
          return { ...curr, frameId: res.ok ? res.frameId : null, uploadStatus: res.ok ? 'ok' : 'failed' }
        })
      })
    } finally {
      setShooting(false)
    }
  }

  if (!online && showOffline) {
    return <OfflineScreen
      queue={uploadQueue.current}
      onRetry={() => { processQueue(); setShowOffline(false) }}
      onContinue={() => setShowOffline(false)}
    />
  }

  if (preview) {
    return <FramePreview
      blobUrl={preview.url}
      frameNum={preview.frameNum}
      captureRatio={preview.ratio}
      uploadStatus={preview.uploadStatus}
      canSign={preview.canSign}
      onShootMore={() => { setPreview(null); start(facingMode) }}
      onSign={async () => {
        // Дождаться upload если ещё в процессе
        let frameId = preview.frameId
        if (!frameId && uploadPromiseRef.current) {
          const res = await uploadPromiseRef.current
          if (res.ok) frameId = res.frameId
        }
        if (!frameId) return // upload failed — кнопка покажет ошибку
        navigate(`/g/${shortCode}/sign/${frameId}`, {
          state: {
            photoUrl: preview.url,
            ratio: preview.ratio,
            frameNum: preview.frameNum,
            guestName: sessionStorage.getItem('guest_name') ?? 'Гость',
          },
        })
      }}
    />
  }

  // ── shared style helpers ────────────────────────────────────────────────────
  const rot = isLandscape ? 'rotate(90deg)' : 'none'
  const rotTransition = 'transform 0.25s ease'

  const iconBtn: React.CSSProperties = {
    width: 36, height: 36, borderRadius: '50%',
    background: 'rgba(0,0,0,0.35)',
    backdropFilter: 'blur(6px)', WebkitBackdropFilter: 'blur(6px)',
    border: '1px solid rgba(255,255,255,0.12)',
    color: 'rgba(240,230,210,0.75)',
    cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
    flexShrink: 0,
  }

  const camOverlayBtn: React.CSSProperties = {
    ...iconBtn,
    position: 'absolute', bottom: 12, zIndex: 15,
    width: 38, height: 38,
  }

  return (
    <div style={{ position: 'fixed', inset: 0, display: 'flex', flexDirection: 'column', overflow: 'hidden', userSelect: 'none', background: '#16100c' }}>

      {/* ── Upload / offline banners ──────────────────────────────────────── */}
      {uploadQueue.current.length > 0 && online && (
        <div style={{ position: 'relative', zIndex: 30, background: 'var(--shutter)', padding: '8px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontFamily: 'Inter, sans-serif', fontSize: 13, color: '#fff', flexShrink: 0 }}>
          <span>{uploadQueue.current.length} кадр{uploadQueue.current.length > 1 ? 'а' : ''} в очереди</span>
          <button onClick={processQueue} disabled={retrying} style={{ background: 'rgba(255,255,255,.2)', border: 'none', color: '#fff', cursor: 'pointer', fontSize: 12, fontFamily: 'Inter, sans-serif', padding: '4px 10px', borderRadius: 6 }}>
            {retrying ? '...' : 'Повторить'}
          </button>
        </div>
      )}
      {!online && (
        <div onClick={() => setShowOffline(true)} style={{ position: 'relative', zIndex: 30, background: 'var(--shutter)', padding: '8px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', fontFamily: 'Inter, sans-serif', fontSize: 13, color: '#fff', cursor: 'pointer', flexShrink: 0 }}>
          <span>Нет сети — кадры сохранены</span>
          <span style={{ opacity: 0.8 }}>→</span>
        </div>
      )}

      {/* ── Top bar ───────────────────────────────────────────────────────── */}
      <div style={{
        flexShrink: 0, zIndex: 20,
        paddingTop: 'env(safe-area-inset-top, 0px)',
        background: 'linear-gradient(to bottom, rgba(0,0,0,0.6) 0%, transparent 100%)',
      }}>
        <div style={{ padding: '10px 16px 12px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 8 }}>

          {/* Left: back + film label (text NOT rotated) */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
            <button
              onClick={() => navigate(`/g/${shortCode}/waiting`)}
              aria-label="Выйти"
              style={iconBtn}
            >
              <span style={{ display: 'flex', transform: rot, transition: rotTransition }}>
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <line x1="19" y1="12" x2="5" y2="12"/><polyline points="11 18 5 12 11 6"/>
                </svg>
              </span>
            </button>

            {/* Film label & aperture — никогда не вращаются */}
            <div style={{
              fontFamily: 'JetBrains Mono, monospace', fontSize: 10,
              letterSpacing: '.14em', color: 'rgba(255,179,71,0.65)',
              display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0,
            }}>
              <span style={{ width: 4, height: 4, borderRadius: '50%', background: '#D54B3D', flexShrink: 0 }} />
              {lutLabel}
              <span style={{ width: 1, height: 10, background: 'rgba(255,179,71,.22)', flexShrink: 0 }} />
              <span style={{ opacity: .55 }}>ƒ 2.8</span>
            </div>
          </div>

          {/* Right: rotate toggle */}
          <button
            onClick={() => setIsLandscape((v) => !v)}
            aria-label={isLandscape ? 'Портретный кадр' : 'Горизонтальный кадр'}
            title={isLandscape ? 'Вернуть портрет' : 'Горизонтальный снимок'}
            style={{ ...iconBtn, background: isLandscape ? 'rgba(255,179,71,0.15)' : 'rgba(0,0,0,0.35)', borderColor: isLandscape ? 'rgba(255,179,71,0.35)' : 'rgba(255,255,255,0.12)', color: isLandscape ? '#FFB347' : 'rgba(240,230,210,0.75)' }}
          >
            <span style={{ display: 'flex', transform: rot, transition: rotTransition }}>
              <ICRotate />
            </span>
          </button>
        </div>
      </div>

      {/* ── Camera box ────────────────────────────────────────────────────── */}
      <div style={{ flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
        {!error ? (
          <div style={{
            position: 'relative', overflow: 'hidden', borderRadius: 6,
            background: '#050302',
            width: '100%',
            aspectRatio: String(streamRatio),
            maxHeight: '100%',
            boxShadow: '0 8px 32px rgba(0,0,0,.65), 0 0 0 1px rgba(255,179,71,.04)',
          }}>
            {/* Video — fills the box, ratio matched to stream so no bars/zoom */}
            <video
              ref={videoRef}
              playsInline muted
              onLoadedMetadata={(e) => {
                const v = e.currentTarget
                if (v.videoWidth && v.videoHeight) setStreamRatio(v.videoWidth / v.videoHeight)
              }}
              style={{
                position: 'absolute', inset: 0,
                width: '100%', height: '100%', objectFit: 'cover',
                transform: facingMode === 'user' ? 'scaleX(-1)' : undefined,
              }}
            />

            {/* Corner brackets */}
            {(['tl', 'tr', 'bl', 'br'] as const).map((id) => (
              <div key={id} style={{
                position: 'absolute', pointerEvents: 'none', zIndex: 5,
                width: 18, height: 18,
                top: id.startsWith('t') ? 7 : undefined,
                bottom: id.startsWith('b') ? 7 : undefined,
                left: id.endsWith('l') ? 7 : undefined,
                right: id.endsWith('r') ? 7 : undefined,
                borderTop: id.startsWith('t') ? '1.5px solid rgba(255,179,71,0.5)' : 'none',
                borderBottom: id.startsWith('b') ? '1.5px solid rgba(255,179,71,0.5)' : 'none',
                borderLeft: id.endsWith('l') ? '1.5px solid rgba(255,179,71,0.5)' : 'none',
                borderRight: id.endsWith('r') ? '1.5px solid rgba(255,179,71,0.5)' : 'none',
                borderRadius: id === 'tl' ? '3px 0 0 0' : id === 'tr' ? '0 3px 0 0' : id === 'bl' ? '0 0 0 3px' : '0 0 3px 0',
              }} />
            ))}

            {/* Flash button — overlay bottom-left */}
            <button
              onClick={() => setFlashOn((v) => !v)}
              aria-label={flashOn ? 'Отключить вспышку' : 'Включить вспышку'}
              style={{
                ...camOverlayBtn, left: 12,
                background: flashOn ? 'rgba(255,179,71,0.22)' : 'rgba(0,0,0,0.42)',
                borderColor: flashOn ? 'rgba(255,179,71,0.4)' : 'rgba(255,255,255,0.12)',
                color: flashOn ? '#FFB347' : 'rgba(240,230,210,0.7)',
              }}
            >
              <span style={{ display: 'flex', transform: rot, transition: rotTransition }}>
                {flashOn ? <ICFlash /> : <ICFlashOff />}
              </span>
            </button>

            {/* Flip button — overlay bottom-right */}
            <button
              onClick={() => setFacingMode((m) => m === 'environment' ? 'user' : 'environment')}
              aria-label="Переключить камеру"
              style={{ ...camOverlayBtn, right: 12 }}
            >
              <span style={{ display: 'flex', transform: rot, transition: rotTransition }}>
                <ICFlip />
              </span>
            </button>

            {/* Screen flash overlay */}
            {screenFlashing && (
              <div style={{ position: 'absolute', inset: 0, zIndex: 50, background: '#fff', pointerEvents: 'none' }} />
            )}
          </div>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 12, padding: 32, textAlign: 'center' }}>
            <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke="rgba(240,230,210,.35)" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 7h4l2-3h6l2 3h4v13H3z"/><circle cx="12" cy="13" r="4"/>
            </svg>
            <p style={{ margin: 0, fontSize: 15, color: 'var(--dr-text)' }}>Нет доступа к камере</p>
            <p style={{ margin: 0, fontSize: 13, color: 'rgba(240,230,210,.4)' }}>{error}</p>
          </div>
        )}
      </div>

      {/* ── Bottom bar ────────────────────────────────────────────────────── */}
      <div style={{
        flexShrink: 0, zIndex: 20,
        background: 'linear-gradient(to top, rgba(0,0,0,0.6) 0%, transparent 100%)',
        padding: '12px 28px',
        paddingBottom: 'max(env(safe-area-inset-bottom, 16px), 16px)',
      }}>
        <div style={{ height: 80, display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>

          {/* Counter — bottom-left, rotates */}
          <div style={{ transform: rot, transition: rotTransition, flexShrink: 0 }}>
            {framesLeft !== null
              ? <FilmCounter frames={framesLeft} />
              : <div style={{ width: 60, height: 36 }} />
            }
          </div>

          {/* Shutter — center */}
          <button
            onClick={handleShutter}
            disabled={!ready || shooting || framesLeft === 0}
            aria-label="Снять фото"
            style={{
              width: 72, height: 72, borderRadius: '50%',
              background: 'var(--dr-text)',
              border: '2px solid rgba(255,179,71,0.35)',
              boxShadow: '0 0 0 3px rgba(0,0,0,0.45), 0 0 0 5px rgba(255,179,71,0.3), 0 0 24px rgba(255,179,71,0.35)',
              cursor: ready && !shooting && framesLeft !== 0 ? 'pointer' : 'not-allowed',
              transition: 'transform 0.1s',
              transform: shooting ? 'scale(0.88)' : 'scale(1)',
              flexShrink: 0,
              opacity: !ready || framesLeft === 0 ? 0.5 : 1,
            }}
          />

          {/* Recent shots — bottom-right, rotates */}
          <div style={{ transform: rot, transition: rotTransition, flexShrink: 0 }}>
            <RecentStack
              shots={recentShots}
              onOpen={(s) => setPreview({ url: s.url, frameNum: s.frameNum, ratio: s.ratio, frameId: null, uploadStatus: 'ok', canSign: false })}
            />
          </div>
        </div>
      </div>

    </div>
  )
}
