import { useEffect, useRef, useState } from 'react'
import { useLocation, useNavigate, useParams } from 'react-router-dom'
import { guestApi } from '../../api/client'

interface SignState {
  photoUrl: string
  ratio: number
  frameNum: number
  guestName?: string
}

const MAX = 120

export default function CaptionScreen() {
  const { shortCode, frameId } = useParams<{ shortCode: string; frameId: string }>()
  const navigate = useNavigate()
  const { state } = useLocation() as { state: SignState | null }
  const inputRef = useRef<HTMLTextAreaElement>(null)

  const [text, setText] = useState('')
  const [savedText, setSavedText] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [showLeaveModal, setShowLeaveModal] = useState(false)
  const [savingPhoto, setSavingPhoto] = useState(false)

  useEffect(() => {
    if (!state?.photoUrl) {
      navigate(`/g/${shortCode}/camera`, { replace: true })
      return
    }
    inputRef.current?.focus()
  }, [state, navigate, shortCode])

  if (!state?.photoUrl) return null

  const hasUnsaved = text.trim().length > 0 && savedText === null

  const handleBack = () => {
    if (hasUnsaved) {
      setShowLeaveModal(true)
    } else {
      navigate(`/g/${shortCode}/sign/${frameId}`, { state })
    }
  }

  const handleSave = async () => {
    const trimmed = text.trim()
    if (!trimmed || !frameId) return
    setSaving(true)
    setError(null)
    try {
      await guestApi.updateFrame(frameId, { caption: trimmed })
      setSavedText(trimmed)
    } catch (e) {
      setError('Не удалось сохранить. Попробуйте ещё раз.')
    } finally {
      setSaving(false)
    }
  }

  const handleSavePhotoCard = async () => {
    if (!state || !savedText || savingPhoto) return
    setSavingPhoto(true)
    try {
      const img = new Image()
      // НЕ ставим crossOrigin для blob:/data: URL — ломает загрузку
      const isRemote = /^https?:/.test(state.photoUrl)
      if (isRemote) img.crossOrigin = 'anonymous'
      await new Promise<void>((resolve, reject) => {
        img.onload = () => resolve()
        img.onerror = () => reject(new Error('image load failed'))
        img.src = state.photoUrl
      })
      // Build a polaroid-style canvas: white frame around photo + caption below
      const photoW = 1200
      const photoH = Math.round(photoW / state.ratio)
      const padX = 60
      const padTop = 60
      const captionH = 240
      const canvas = document.createElement('canvas')
      canvas.width = photoW + padX * 2
      canvas.height = photoH + padTop + captionH
      const ctx = canvas.getContext('2d')!
      ctx.fillStyle = '#F6F2E8'
      ctx.fillRect(0, 0, canvas.width, canvas.height)
      ctx.drawImage(img, padX, padTop, photoW, photoH)
      // Caption
      ctx.fillStyle = '#2F2A24'
      ctx.font = 'italic 64px "Caveat", cursive'
      ctx.textAlign = 'center'
      ctx.textBaseline = 'middle'
      // word wrap
      const words = savedText.split(/\s+/)
      const lines: string[] = []
      let current = ''
      const maxWidth = canvas.width - padX * 2
      for (const w of words) {
        const candidate = current ? `${current} ${w}` : w
        if (ctx.measureText(candidate).width <= maxWidth) {
          current = candidate
        } else {
          if (current) lines.push(current)
          current = w
        }
      }
      if (current) lines.push(current)
      const lineH = 76
      const totalH = lines.length * lineH
      const startY = photoH + padTop + (captionH - totalH) / 2 + lineH / 2
      lines.forEach((line, i) => {
        ctx.fillText(line, canvas.width / 2, startY + i * lineH)
      })

      canvas.toBlob(async (blob) => {
        if (!blob) { setSavingPhoto(false); setError('Не удалось создать фотокарточку.'); return }
        const file = new File([blob], `impomento-kdr-${state.frameNum}.jpg`, { type: 'image/jpeg' })
        // iOS Safari: share sheet даёт «Сохранить в Фото»
        if (navigator.canShare?.({ files: [file] })) {
          try { await navigator.share({ files: [file] }) } catch {}
        } else {
          const url = URL.createObjectURL(blob)
          const a = document.createElement('a')
          a.href = url
          a.download = file.name
          document.body.appendChild(a)
          a.click()
          document.body.removeChild(a)
          setTimeout(() => URL.revokeObjectURL(url), 10_000)
        }
        setSavingPhoto(false)
      }, 'image/jpeg', 0.92)
    } catch (e) {
      console.error('savePhotoCard failed', e)
      setError('Не удалось сохранить фотокарточку.')
      setSavingPhoto(false)
    }
  }

  // ── Display mode (after save) ────────────────────────────────────────────
  if (savedText !== null) {
    return (
      <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
        <div style={{ paddingTop: 'max(env(safe-area-inset-top, 12px), 12px)', padding: '12px 14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <button onClick={() => navigate(`/g/${shortCode}/camera`)} aria-label="К камере"
            style={{ width: 34, height: 34, borderRadius: '50%', background: 'rgba(0,0,0,0.06)', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--ink-2)' }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="11 18 5 12 11 6"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
          </button>
          <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '4px 10px', borderRadius: 999, background: 'rgba(201,136,30,.12)', color: 'var(--amber)', fontFamily: 'JetBrains Mono, monospace', fontSize: 9, letterSpacing: '.1em', textTransform: 'uppercase' }}>
            <svg width="9" height="9" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="3"><polyline points="20 6 9 17 4 12"/></svg>
            Подписано
          </div>
          <button onClick={handleSavePhotoCard} disabled={savingPhoto} aria-label="Сохранить фотокарточку"
            style={{ width: 34, height: 34, borderRadius: '50%', background: 'rgba(0,0,0,0.06)', border: 'none', cursor: savingPhoto ? 'wait' : 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--ink-2)', opacity: savingPhoto ? 0.5 : 1 }}
          >
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8"><path d="M12 4v12"/><polyline points="6 12 12 18 18 12"/><line x1="4" y1="21" x2="20" y2="21"/></svg>
          </button>
        </div>

        <div style={{ padding: '18px 24px 0', textAlign: 'center' }}>
          <div style={{ display: 'inline-block', background: 'var(--paper)', padding: '14px 14px 0', borderRadius: 4, boxShadow: '0 20px 50px -8px rgba(0,0,0,.25)', transform: 'rotate(-1deg)' }}>
            <div style={{ width: 220, aspectRatio: String(state.ratio), background: '#000', borderRadius: 2, overflow: 'hidden' }}>
              <img src={state.photoUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
            </div>
            <div style={{ height: 38, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: 'Caveat, cursive', fontSize: 20, color: 'var(--ink-2)' }}>
              {state.guestName ?? 'Гость'}
            </div>
          </div>
        </div>

        <div style={{ padding: '26px 24px 0' }}>
          <div style={{ fontFamily: 'Caveat, cursive', fontStyle: 'italic', fontSize: 24, lineHeight: 1.2, color: 'var(--ink-2)', textAlign: 'center' }}>
            {savedText}
          </div>
        </div>

        <div style={{ flex: 1 }} />

        <div style={{ padding: '12px 16px max(env(safe-area-inset-bottom, 16px), 16px)', display: 'flex', flexDirection: 'column', gap: 8 }}>
          <button onClick={() => navigate(`/g/${shortCode}/camera`)}
            style={{ width: '100%', padding: '14px 16px', borderRadius: 12, background: 'var(--amber)', color: '#fff', border: 'none', cursor: 'pointer', fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8 }}
          >
            Вернуться к съёмке
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="13 6 19 12 13 18"/></svg>
          </button>
          <button onClick={() => navigate(`/g/${shortCode}/waiting`)}
            style={{ width: '100%', padding: '14px 16px', borderRadius: 12, background: 'transparent', color: 'var(--ink-3)', border: '1px solid var(--line)', cursor: 'pointer', fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14 }}
          >
            К альбому
          </button>
        </div>
      </div>
    )
  }

  // ── Input mode ───────────────────────────────────────────────────────────
  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
      <div style={{ paddingTop: 'max(env(safe-area-inset-top, 12px), 12px)', padding: '12px 14px', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
        <button onClick={handleBack} aria-label="Назад"
          style={{ width: 34, height: 34, borderRadius: '50%', background: 'rgba(0,0,0,0.06)', border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--ink-2)' }}
        >
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2"><polyline points="11 18 5 12 11 6"/><line x1="5" y1="12" x2="19" y2="12"/></svg>
        </button>
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.14em', color: 'var(--ink-3)' }}>
          ПОДПИСЬ К КАДРУ {String(state.frameNum).padStart(2, '0')}
        </div>
        <div style={{ width: 34 }} />
      </div>

      <div style={{ padding: '8px 24px 0', textAlign: 'center' }}>
        <div style={{ display: 'inline-block', background: 'var(--paper)', padding: '12px 12px 0', borderRadius: 3, boxShadow: '0 8px 24px rgba(0,0,0,.25)', transform: 'rotate(-1.5deg)' }}>
          <div style={{ width: 130, aspectRatio: String(state.ratio), background: '#000', borderRadius: 2, overflow: 'hidden' }}>
            <img src={state.photoUrl} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} />
          </div>
          <div style={{ height: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', fontFamily: 'Caveat, cursive', fontSize: 14, color: 'var(--ink-2)' }}>
            {state.guestName ?? 'Гость'}
          </div>
        </div>
      </div>

      <div style={{ padding: '18px 24px 0' }}>
        <h2 style={{ fontFamily: 'Fraunces, serif', fontWeight: 500, fontSize: 22, lineHeight: 1.15, marginBottom: 6, color: 'var(--ink)' }}>
          Оставьте комментарий к снимку
        </h2>
        <p style={{ fontSize: 12, color: 'var(--ink-3)', lineHeight: 1.4, marginBottom: 14 }}>
          Несколько слов о запечатлённом моменте. Подпись сохранится в альбоме.
        </p>
        <textarea
          ref={inputRef}
          value={text}
          onChange={(e) => setText(e.target.value.slice(0, MAX))}
          placeholder="Закат, который мы так ждали…"
          rows={3}
          style={{ width: '100%', background: 'rgba(0,0,0,0.04)', border: '1px solid var(--line)', borderRadius: 10, padding: 14, fontFamily: 'Inter, sans-serif', fontSize: 14, color: 'var(--ink)', resize: 'none' }}
        />
        <div style={{ fontFamily: 'JetBrains Mono, monospace', fontSize: 10, letterSpacing: '.1em', color: text.length >= MAX ? 'var(--shutter)' : 'var(--ink-4)', textAlign: 'right', marginTop: 6 }}>
          {text.length} / {MAX}
        </div>
        {error && (
          <div style={{ marginTop: 8, fontSize: 12, color: 'var(--shutter)' }}>{error}</div>
        )}
      </div>

      <div style={{ flex: 1 }} />

      <div style={{ padding: '12px 16px max(env(safe-area-inset-bottom, 16px), 16px)', display: 'flex', flexDirection: 'column', gap: 8 }}>
        <button onClick={handleSave} disabled={!text.trim() || saving}
          style={{ width: '100%', padding: '14px 16px', borderRadius: 12, background: 'var(--amber)', color: '#fff', border: 'none', cursor: (!text.trim() || saving) ? 'not-allowed' : 'pointer', fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14, opacity: (!text.trim() || saving) ? 0.5 : 1 }}
        >
          {saving ? 'Сохраняем…' : 'Сохранить подпись'}
        </button>
        <button onClick={handleBack}
          style={{ width: '100%', padding: '14px 16px', borderRadius: 12, background: 'transparent', color: 'var(--ink-3)', border: '1px solid var(--line)', cursor: 'pointer', fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 14 }}
        >
          Пропустить
        </button>
      </div>

      {showLeaveModal && (
        <div style={{ position: 'fixed', inset: 0, background: 'rgba(0,0,0,.55)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 20, zIndex: 100 }}>
          <div style={{ background: 'var(--paper)', borderRadius: 16, padding: 20, width: '100%', maxWidth: 340, boxShadow: '0 20px 60px rgba(0,0,0,.4)' }}>
            <h3 style={{ fontFamily: 'Fraunces, serif', fontWeight: 500, fontSize: 18, marginBottom: 8, color: 'var(--ink)' }}>
              Подпись не сохранена
            </h3>
            <p style={{ fontSize: 13, color: 'var(--ink-3)', lineHeight: 1.5, marginBottom: 16 }}>
              Если вернуться сейчас, то текст не попадёт в альбом. Сохранить подпись или продолжить без неё?
            </p>
            <div style={{ display: 'flex', gap: 8 }}>
              <button onClick={() => { setShowLeaveModal(false); navigate(`/g/${shortCode}/sign/${frameId}`, { state }) }}
                style={{ flex: 1, padding: '12px', borderRadius: 12, background: 'transparent', color: 'var(--ink-3)', border: '1px solid var(--line)', cursor: 'pointer', fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 13 }}
              >
                Без подписи
              </button>
              <button onClick={() => { setShowLeaveModal(false); handleSave() }}
                style={{ flex: 1, padding: '12px', borderRadius: 12, background: 'var(--amber)', color: '#fff', border: 'none', cursor: 'pointer', fontFamily: 'Inter, sans-serif', fontWeight: 600, fontSize: 13 }}
              >
                Сохранить
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  )
}
