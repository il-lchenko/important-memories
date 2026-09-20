import { useState, useCallback, useEffect, useRef } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import ReportModal from './ReportModal'
import { guestApi } from '../../api/client'

interface Frame {
  id: string
  guest_id: string | null
  guest_name: string
  guest_avatar_url?: string | null
  captured_at: string
  thumbnail_url: string | null
  preview_url: string | null
  full_url: string
  width: number
  height: number
  is_mine: boolean
  caption?: string | null
  voice_url?: string | null
  voice_duration_ms?: number | null
  voice_peaks?: number[] | null
  rotation?: number
}

function formatTime(iso: string): string {
  return new Date(iso).toLocaleTimeString('ru', { hour: '2-digit', minute: '2-digit' })
}

function IcBtn({ onClick, children, disabled }: { onClick?: () => void; children: React.ReactNode; disabled?: boolean }) {
  return (
    <button
      onClick={onClick}
      disabled={disabled}
      style={{
        width: 36, height: 36, borderRadius: 18,
        background: 'rgba(255,255,255,.08)', color: 'var(--dr-text)',
        border: 'none', cursor: disabled ? 'default' : 'pointer',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        backdropFilter: 'blur(8px)',
        opacity: disabled ? 0 : 1,
        transition: 'opacity 0.15s',
      }}
    >
      {children}
    </button>
  )
}

export default function FrameFullscreen() {
  const { shortCode, token, frameIndex } = useParams<{ shortCode?: string; token?: string; frameIndex: string }>()
  const navigate = useNavigate()
  const { state } = useLocation() as { state: { frames: Frame[]; totalFrames: number } | null }
  // Публичный режим: открыт по /a/:token/f/:idx. Редактирование запрещено,
  // ротация работает только локально, кнопка «Жалоба» скрыта, «Скачать» и
  // «Поделиться» доступны, автор виден.
  const isPublic = Boolean(token)

  const [showReport, setShowReport] = useState(false)
  const [saving, setSaving] = useState(false)
  const [currentIndex, setCurrentIndex] = useState(() => parseInt(frameIndex ?? '0', 10))
  const [rotation, setRotation] = useState(0)
  const [initialRotation, setInitialRotation] = useState(0)
  const [savingRotation, setSavingRotation] = useState(false)
  const [rotationToast, setRotationToast] = useState<string | null>(null)
  const touchStartX = useRef<number | null>(null)

  const frames: Frame[] = state?.frames ?? []
  const totalFrames: number = state?.totalFrames ?? frames.length
  const frame = frames[currentIndex] ?? null

  const hasPrev = currentIndex > 0
  const hasNext = currentIndex < frames.length - 1

  // Sync rotation from frame data whenever the displayed frame changes
  useEffect(() => {
    const r = frame?.rotation ?? 0
    setRotation(r)
    setInitialRotation(r)
  }, [frame?.id]) // eslint-disable-line react-hooks/exhaustive-deps

  const rotationDirty = rotation !== initialRotation

  const handleSaveRotation = useCallback(async () => {
    if (!frame || savingRotation) return
    if (isPublic || !frame.is_mine) {
      // В публичном просмотре сохранять на сервер нельзя — ротация только локальная.
      return
    }
    setSavingRotation(true)
    try {
      await guestApi.updateFrame(frame.id, { rotation: rotation as 0 | 90 | 180 | 270 })
      // Мутируем frame в location.state — при возврате в альбом или переоткрытии
      // этого же кадра сохранённая ротация не откатится обратно к серверному значению
      // из stale state.
      frame.rotation = rotation
      setInitialRotation(rotation)
      setRotationToast('Ротация сохранена')
      setTimeout(() => setRotationToast(null), 1600)
    } catch {
      setRotationToast('Не удалось сохранить')
      setTimeout(() => setRotationToast(null), 2000)
    } finally {
      setSavingRotation(false)
    }
  }, [frame, rotation, savingRotation])

  const goTo = useCallback((idx: number) => {
    if (idx >= 0 && idx < frames.length) setCurrentIndex(idx)
  }, [frames.length])

  // Preload adjacent frames — prefer preview (smaller, faster). Fallback for legacy frames.
  useEffect(() => {
    const urls: string[] = []
    if (hasPrev) urls.push(frames[currentIndex - 1].preview_url ?? frames[currentIndex - 1].full_url)
    if (hasNext) urls.push(frames[currentIndex + 1].preview_url ?? frames[currentIndex + 1].full_url)
    urls.forEach((url) => { const img = new Image(); img.src = url })
  }, [currentIndex]) // eslint-disable-line react-hooks/exhaustive-deps

  // Keyboard navigation
  useEffect(() => {
    const handler = (e: KeyboardEvent) => {
      if (e.key === 'ArrowLeft') goTo(currentIndex - 1)
      else if (e.key === 'ArrowRight') goTo(currentIndex + 1)
      else if (e.key === 'Escape') navigate(isPublic ? `/a/${token}` : `/g/${shortCode}/album`)
    }
    window.addEventListener('keydown', handler)
    return () => window.removeEventListener('keydown', handler)
  }, [currentIndex, goTo, navigate, shortCode])

  const handleTouchStart = (e: React.TouchEvent) => {
    touchStartX.current = e.touches[0].clientX
  }
  const handleTouchEnd = (e: React.TouchEvent) => {
    if (touchStartX.current === null) return
    const delta = e.changedTouches[0].clientX - touchStartX.current
    touchStartX.current = null
    if (Math.abs(delta) < 48) return
    if (delta < 0) goTo(currentIndex + 1)
    else goTo(currentIndex - 1)
  }

  const back = () => navigate(isPublic ? `/a/${token}` : `/g/${shortCode}/album`)

  const handleShare = async () => {
    if (!frame) return
    if (navigator.share) {
      try { await navigator.share({ url: frame.full_url }) } catch {}
    } else {
      await navigator.clipboard.writeText(frame.full_url).catch(() => {})
    }
  }

  const handleSave = useCallback(async () => {
    if (!frame || saving) return
    setSaving(true)
    try {
      const res = await fetch(frame.full_url)
      if (!res.ok) throw new Error(`${res.status}`)
      const blob = await res.blob()
      const file = new File([blob], `impomento-${currentIndex + 1}.jpg`, { type: 'image/jpeg' })
      // iOS Safari: share sheet lets user tap "Save to Photos"
      if (navigator.canShare?.({ files: [file] })) {
        await navigator.share({ files: [file] })
        return
      }
      // Android / desktop
      const objUrl = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = objUrl
      a.download = file.name
      document.body.appendChild(a)
      a.click()
      document.body.removeChild(a)
      setTimeout(() => URL.revokeObjectURL(objUrl), 10_000)
    } catch {
      window.open(frame.full_url, '_blank', 'noopener')
    } finally {
      setSaving(false)
    }
  }, [frame, currentIndex, saving])

  if (!frame) {
    return (
      <div style={{ minHeight: '100dvh', background: 'var(--dark)', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 16 }}>
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
      <div style={{ paddingTop: 'max(env(safe-area-inset-top, 12px), 12px)', paddingLeft: 16, paddingRight: 16, paddingBottom: 8, display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexShrink: 0 }}>
        <IcBtn onClick={back}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <line x1="6" y1="6" x2="18" y2="18" /><line x1="18" y1="6" x2="6" y2="18" />
          </svg>
        </IcBtn>

        <span style={{ fontFamily: 'Inter, sans-serif', fontSize: 11, letterSpacing: '.14em', color: 'rgba(240,230,210,.65)' }}>
          {currentIndex + 1} / {totalFrames}
        </span>

        {isPublic ? (
          <span style={{ width: 36, height: 36 }} />
        ) : (
          <IcBtn onClick={() => setShowReport(true)}>
            <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <circle cx="12" cy="12" r="1.5" fill="currentColor" /><circle cx="6" cy="12" r="1.5" fill="currentColor" /><circle cx="18" cy="12" r="1.5" fill="currentColor" />
            </svg>
          </IcBtn>
        )}
      </div>

      {/* Dot indicators — between counter and photo */}
      {frames.length > 1 && frames.length <= 20 && (
        <div style={{ display: 'flex', justifyContent: 'center', gap: 5, padding: '6px 0 10px', flexShrink: 0 }}>
          {frames.map((_, i) => (
            <div
              key={i}
              style={{
                width: i === currentIndex ? 16 : 5,
                height: 5, borderRadius: 3,
                background: i === currentIndex ? 'rgba(255,179,71,.9)' : 'rgba(255,255,255,.25)',
                transition: 'width 0.2s, background 0.2s',
              }}
            />
          ))}
        </div>
      )}

      {/* Photo with swipe */}
      <div
        style={{ flex: 1, position: 'relative', overflow: 'hidden', minHeight: 0 }}
        onTouchStart={handleTouchStart}
        onTouchEnd={handleTouchEnd}
      >
        <RotatedImage
          key={frame.id}
          src={frame.preview_url ?? frame.full_url}
          rotation={rotation}
          naturalWidth={frame.width}
          naturalHeight={frame.height}
        />

        {/* Prev arrow — left edge tap zone */}
        {hasPrev && (
          <button
            onClick={() => goTo(currentIndex - 1)}
            style={{
              position: 'absolute', left: 0, top: 0, bottom: 0, width: 56,
              background: 'none', border: 'none', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'flex-start', paddingLeft: 10,
            }}
            aria-label="Предыдущее фото"
          >
            <div style={{ width: 32, height: 32, borderRadius: 16, background: 'rgba(0,0,0,.35)', backdropFilter: 'blur(6px)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="rgba(240,230,210,.7)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="15 6 9 12 15 18" />
              </svg>
            </div>
          </button>
        )}

        {/* Next arrow — right edge tap zone */}
        {hasNext && (
          <button
            onClick={() => goTo(currentIndex + 1)}
            style={{
              position: 'absolute', right: 0, top: 0, bottom: 0, width: 56,
              background: 'none', border: 'none', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'flex-end', paddingRight: 10,
            }}
            aria-label="Следующее фото"
          >
            <div style={{ width: 32, height: 32, borderRadius: 16, background: 'rgba(0,0,0,.35)', backdropFilter: 'blur(6px)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="rgba(240,230,210,.7)" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                <polyline points="9 6 15 12 9 18" />
              </svg>
            </div>
          </button>
        )}

      </div>

      {/* Caption — сразу под фото, с воздухом. */}
      {frame.caption && (
        <div style={{ flexShrink: 0, padding: '22px 26px 10px', textAlign: 'center' }}>
          <div style={{
            fontFamily: 'Caveat, cursive', fontStyle: 'italic',
            fontSize: 26, lineHeight: 1.28, color: 'rgba(255,179,71,.95)',
            wordBreak: 'break-word', overflowWrap: 'anywhere',
          }}>
            {frame.caption}
          </div>
        </div>
      )}

      {/* Voice player — сразу под фото, тот же ритм что и caption. */}
      {!frame.caption && frame.voice_url && (
        <div style={{ flexShrink: 0, padding: '22px 20px 10px' }}>
          <VoicePlayer
            url={frame.voice_url}
            peaks={frame.voice_peaks ?? null}
            durationMs={frame.voice_duration_ms ?? 0}
          />
        </div>
      )}

      {/* Guest name + capture time — отдельная нижняя мета-полоса. */}
      <div style={{ flexShrink: 0, padding: '18px 20px 6px', display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 12 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, overflow: 'hidden', minWidth: 0, flex: 1 }}>
          <div style={{
            width: 28, height: 28, borderRadius: '50%',
            background: frame.guest_avatar_url ? undefined : 'rgba(255,179,71,0.14)',
            backgroundImage: frame.guest_avatar_url ? `url(${frame.guest_avatar_url})` : undefined,
            backgroundSize: 'cover', backgroundPosition: 'center',
            border: '1px solid rgba(255,179,71,0.35)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0,
            fontFamily: 'Playfair Display, serif', fontSize: 13, fontWeight: 600,
            color: '#FFB347',
          }}>
            {!frame.guest_avatar_url && (frame.guest_name?.[0]?.toUpperCase() ?? '?')}
          </div>
          {/* Caveat cursive имеет overhang на курсивах — без paddingRight последняя
              буква/росчерк обрезается ellipsis'ом даже когда места хватает. */}
          <div style={{
            fontFamily: 'Caveat, cursive', fontSize: 26, lineHeight: 1,
            color: 'rgba(246,242,232,.92)',
            textShadow: '0 1px 3px rgba(0,0,0,.4)',
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            minWidth: 0, flex: 1,
            paddingRight: 6,
          }}>
            {frame.guest_name}
          </div>
        </div>
        <span style={{
          fontFamily: 'Inter, sans-serif', fontSize: 11,
          color: 'rgba(255,179,71,.85)', letterSpacing: '.1em',
          flexShrink: 0,
        }}>
          {formatTime(frame.captured_at)}
        </span>
      </div>

      {/* Actions */}
      <div style={{ flexShrink: 0, padding: '8px 20px 30px', display: 'flex', justifyContent: 'space-around', background: 'var(--dark)' }}>
        {/* Rotate */}
        <button onClick={() => setRotation(r => (r + 90) % 360)} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--dr-text)', fontSize: 11, fontFamily: 'Inter, sans-serif' }}>
          <div style={{ width: 44, height: 44, borderRadius: 14, background: 'rgba(255,255,255,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(8px)' }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/><path d="M3 3v5h5"/>
            </svg>
          </div>
          <span>Повернуть</span>
        </button>

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
        <button onClick={handleSave} disabled={saving} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, background: 'none', border: 'none', cursor: saving ? 'wait' : 'pointer', color: 'var(--dr-text)', fontSize: 11, fontFamily: 'Inter, sans-serif', opacity: saving ? 0.6 : 1 }}>
          <div style={{ width: 44, height: 44, borderRadius: 14, background: 'rgba(255,255,255,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(8px)' }}>
            {saving ? (
              <div style={{ width: 18, height: 18, borderRadius: '50%', border: '2px solid rgba(240,230,210,.3)', borderTopColor: 'var(--dr-text)', animation: 'spin 0.8s linear infinite' }} />
            ) : (
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <path d="M12 4v12" /><polyline points="6 12 12 18 18 12" /><line x1="4" y1="21" x2="20" y2="21" />
              </svg>
            )}
          </div>
          <span>{saving ? '...' : 'Сохранить'}</span>
        </button>

        {/* Report — только для авторизованных гостей */}
        {!isPublic && (
          <button onClick={() => setShowReport(true)} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, background: 'none', border: 'none', cursor: 'pointer', color: 'var(--dr-text)', fontSize: 11, fontFamily: 'Inter, sans-serif' }}>
            <div style={{ width: 44, height: 44, borderRadius: 14, background: 'rgba(255,255,255,.08)', display: 'flex', alignItems: 'center', justifyContent: 'center', backdropFilter: 'blur(8px)', color: 'var(--shutter)' }}>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <circle cx="12" cy="12" r="9" /><line x1="12" y1="8" x2="12" y2="13" /><circle cx="12" cy="16.5" r=".5" fill="currentColor" />
              </svg>
            </div>
            <span>Жалоба</span>
          </button>
        )}
      </div>

      {showReport && (
        <ReportModal frameId={frame.id} onClose={() => setShowReport(false)} />
      )}

      {rotationDirty && frame.is_mine && (
        <div
          style={{
            position: 'fixed',
            left: 20,
            right: 20,
            bottom: 'calc(env(safe-area-inset-bottom, 0px) + 100px)',
            zIndex: 60,
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'space-between',
            gap: 12,
            background: 'rgba(20,14,10,.92)',
            border: '1px solid rgba(255,179,71,.28)',
            borderRadius: 16,
            padding: '12px 14px',
            backdropFilter: 'blur(10px)',
            boxShadow: '0 10px 30px rgba(0,0,0,.45)',
          }}
        >
          <span style={{ fontFamily: 'Inter, sans-serif', fontSize: 13, color: 'rgba(246,242,232,.9)' }}>
            Сохранить ротацию?
          </span>
          <div style={{ display: 'flex', gap: 8 }}>
            <button
              onClick={() => setRotation(initialRotation)}
              disabled={savingRotation}
              style={{
                background: 'transparent', color: 'rgba(246,242,232,.7)',
                border: '1px solid rgba(255,255,255,.15)', borderRadius: 12,
                padding: '8px 14px', fontFamily: 'Inter, sans-serif', fontSize: 13,
                cursor: savingRotation ? 'default' : 'pointer',
              }}
            >
              Отмена
            </button>
            <button
              onClick={handleSaveRotation}
              disabled={savingRotation}
              style={{
                background: 'var(--amber, #C9881E)', color: '#fff',
                border: 'none', borderRadius: 12,
                padding: '8px 16px', fontFamily: 'Inter, sans-serif', fontSize: 13, fontWeight: 600,
                cursor: savingRotation ? 'wait' : 'pointer',
                opacity: savingRotation ? 0.7 : 1,
              }}
            >
              {savingRotation ? '…' : 'Сохранить'}
            </button>
          </div>
        </div>
      )}

      {rotationToast && (
        <div
          style={{
            position: 'fixed',
            left: '50%',
            top: 'calc(env(safe-area-inset-top, 0px) + 60px)',
            transform: 'translateX(-50%)',
            zIndex: 70,
            background: 'rgba(20,14,10,.92)',
            color: 'rgba(255,179,71,.95)',
            border: '1px solid rgba(255,179,71,.28)',
            borderRadius: 999,
            padding: '8px 16px',
            fontFamily: 'Inter, sans-serif',
            fontSize: 13,
            backdropFilter: 'blur(10px)',
          }}
        >
          {rotationToast}
        </div>
      )}

      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  )
}

function RotatedImage({
  src,
  rotation,
  naturalWidth,
  naturalHeight,
}: {
  src: string
  rotation: number
  naturalWidth: number
  naturalHeight: number
}) {
  const wrapRef = useRef<HTMLDivElement>(null)
  const [box, setBox] = useState({ w: 0, h: 0 })

  useEffect(() => {
    const el = wrapRef.current
    if (!el) return
    const update = () => {
      const r = el.getBoundingClientRect()
      setBox({ w: r.width, h: r.height })
    }
    update()
    const ro = new ResizeObserver(update)
    ro.observe(el)
    return () => ro.disconnect()
  }, [])

  const swap = rotation === 90 || rotation === 270
  const ar = naturalWidth > 0 && naturalHeight > 0 ? naturalWidth / naturalHeight : 1
  const effAR = swap ? 1 / ar : ar

  let renderedW = 0
  let renderedH = 0
  if (box.w > 0 && box.h > 0) {
    renderedW = box.w
    renderedH = renderedW / effAR
    if (renderedH > box.h) {
      renderedH = box.h
      renderedW = renderedH * effAR
    }
  }

  // CSS-rotate вращает layout box вокруг центра. Чтобы после rotate картинка
  // заняла effective area (renderedW × renderedH) — задаём img в размерах ДО
  // поворота, т.е. при swap width=renderedH, height=renderedW.
  const imgW = swap ? renderedH : renderedW
  const imgH = swap ? renderedW : renderedH

  return (
    <div
      ref={wrapRef}
      style={{
        position: 'absolute', inset: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}
    >
      {imgW > 0 && (
        <img
          src={src}
          alt=""
          style={{
            width: imgW,
            height: imgH,
            display: 'block',
            transform: `rotate(${rotation}deg)`,
            transformOrigin: 'center center',
            transition: 'transform 0.3s ease, width 0.2s ease, height 0.2s ease',
          }}
        />
      )}
    </div>
  )
}

function VoicePlayer({ url, peaks, durationMs }: { url: string; peaks: number[] | null; durationMs: number }) {
  const audioRef = useRef<HTMLAudioElement | null>(null)
  const [playing, setPlaying] = useState(false)
  const [position, setPosition] = useState(0)

  useEffect(() => () => {
    if (audioRef.current) {
      audioRef.current.pause()
      audioRef.current = null
    }
  }, [])

  // Reset state when url changes (different frame)
  useEffect(() => {
    if (audioRef.current) {
      audioRef.current.pause()
      audioRef.current = null
    }
    setPlaying(false)
    setPosition(0)
  }, [url])

  const toggle = () => {
    if (!audioRef.current) {
      audioRef.current = new Audio(url)
      audioRef.current.addEventListener('timeupdate', () => {
        const el = audioRef.current
        if (el && el.duration > 0) setPosition(el.currentTime / el.duration)
      })
      audioRef.current.addEventListener('ended', () => {
        setPlaying(false)
        setPosition(0)
      })
    }
    if (playing) {
      audioRef.current.pause()
      setPlaying(false)
    } else {
      audioRef.current.play().catch(() => setPlaying(false))
      setPlaying(true)
    }
  }

  const displayPeaks = peaks && peaks.length > 0 ? peaks : new Array(20).fill(0.4)
  const totalSec = Math.max(0, Math.round(durationMs / 1000))

  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, background: 'rgba(255,179,71,0.08)', border: '1px solid rgba(255,179,71,0.18)', borderRadius: 22, padding: '6px 14px 6px 6px' }}>
      <button onClick={toggle} aria-label={playing ? 'Пауза' : 'Воспроизвести'}
        style={{ width: 32, height: 32, borderRadius: '50%', background: 'var(--amber)', color: '#fff', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}
      >
        {playing ? (
          <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><rect x="6" y="4" width="4" height="16"/><rect x="14" y="4" width="4" height="16"/></svg>
        ) : (
          <svg width="12" height="12" viewBox="0 0 24 24" fill="currentColor"><polygon points="5 3 19 12 5 21 5 3"/></svg>
        )}
      </button>
      <div style={{ display: 'flex', alignItems: 'center', gap: 2, height: 24, flex: 1 }}>
        {displayPeaks.map((p, i) => {
          const ratio = i / Math.max(1, displayPeaks.length - 1)
          const isPlayed = ratio < position
          return (
            <div key={i} style={{ width: 3, height: `${Math.max(12, p * 100)}%`, background: isPlayed ? 'var(--shutter)' : 'rgba(255,179,71,.9)', borderRadius: 1.5 }} />
          )
        })}
      </div>
      <span style={{ fontFamily: 'Inter, sans-serif', fontSize: 10, color: 'rgba(255,179,71,.7)', flexShrink: 0 }}>
        0:{String(totalSec).padStart(2, '0')}
      </span>
    </div>
  )
}
