import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { guestApi, uploadPutBlob } from '../../api/client'

interface SessionState {
  name: string
  avatar_url: string | null
  bio: string | null
  frames_used: number
  frames_remaining: number
  event_title: string
}

function initialFromName(name: string): string {
  const t = name.trim()
  return t ? t.charAt(0).toUpperCase() : '?'
}

async function resizeToSquareJpeg(file: File): Promise<Blob> {
  const bitmap = await createImageBitmap(file)
  const size = Math.min(bitmap.width, bitmap.height)
  const sx = Math.floor((bitmap.width - size) / 2)
  const sy = Math.floor((bitmap.height - size) / 2)
  const canvas = document.createElement('canvas')
  canvas.width = 512
  canvas.height = 512
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Canvas 2D unavailable')
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(bitmap, sx, sy, size, size, 0, 0, 512, 512)
  return await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob(
      (b) => (b ? resolve(b) : reject(new Error('toBlob failed'))),
      'image/jpeg',
      0.85,
    )
  })
}

export default function ProfileScreen() {
  const { shortCode } = useParams<{ shortCode: string }>()
  const navigate = useNavigate()
  const [session, setSession] = useState<SessionState | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [uploading, setUploading] = useState(false)
  const [renaming, setRenaming] = useState(false)
  const [renameValue, setRenameValue] = useState('')
  const [renameSaving, setRenameSaving] = useState(false)
  const [toast, setToast] = useState<string | null>(null)
  const fileRef = useRef<HTMLInputElement>(null)

  useEffect(() => {
    let cancelled = false
    guestApi
      .getSession()
      .then(({ data }) => {
        if (cancelled) return
        setSession({
          name: data.name ?? '—',
          avatar_url: data.avatar_url ?? null,
          bio: data.bio ?? null,
          frames_used: data.frames_used,
          frames_remaining: data.frames_remaining,
          event_title: data.event?.title ?? 'Событие',
        })
      })
      .catch(() => {
        if (!cancelled) setError('Не удалось загрузить профиль')
      })
      .finally(() => {
        if (!cancelled) setLoading(false)
      })
    return () => {
      cancelled = true
    }
  }, [])

  const flashToast = (msg: string) => {
    setToast(msg)
    setTimeout(() => setToast(null), 2000)
  }

  const handlePickFile = () => fileRef.current?.click()

  const handleFileChange = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    e.target.value = ''
    if (!file || uploading) return
    setUploading(true)
    try {
      const blob = await resizeToSquareJpeg(file)
      const { data: presign } = await guestApi.avatarPresign(blob.size, 'image/jpeg')
      const controller = new AbortController()
      await uploadPutBlob(presign.upload_url, blob, controller.signal)
      const { data: updated } = await guestApi.updateProfile({ avatar_key: presign.avatar_key })
      setSession((prev) =>
        prev
          ? {
              ...prev,
              avatar_url: updated.avatar_url ?? prev.avatar_url,
              bio: updated.bio ?? prev.bio,
              name: updated.name ?? prev.name,
            }
          : prev,
      )
      flashToast('Аватар обновлён')
    } catch (err) {
      console.error('avatar_upload_failed', err)
      flashToast('Не удалось загрузить фото')
    } finally {
      setUploading(false)
    }
  }

  const openRename = () => {
    setRenameValue(session?.name ?? '')
    setRenaming(true)
  }

  const saveRename = async () => {
    const newName = renameValue.trim()
    if (!newName || renameSaving) return
    setRenameSaving(true)
    try {
      const { data } = await guestApi.updateName(newName)
      setSession((prev) => (prev ? { ...prev, name: data.name ?? newName } : prev))
      if (shortCode) {
        localStorage.setItem(`gn_${shortCode}`, newName)
        sessionStorage.setItem('guest_name', newName)
      }
      setRenaming(false)
      flashToast('Имя обновлено')
    } catch {
      flashToast('Не удалось сохранить')
    } finally {
      setRenameSaving(false)
    }
  }

  const back = () => {
    if (shortCode) navigate(`/g/${shortCode}/album`)
    else navigate(-1)
  }

  return (
    <div style={{ minHeight: '100dvh', background: 'var(--paper)', display: 'flex', flexDirection: 'column' }}>
      {/* Top bar */}
      <div style={{ padding: '14px 20px 8px', display: 'flex', alignItems: 'center', gap: 10 }}>
        <button
          onClick={back}
          aria-label="Назад"
          style={{
            width: 40, height: 40, borderRadius: 20,
            background: 'var(--paper-2)', border: 'none', cursor: 'pointer',
            color: 'var(--ink-2)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}
        >
          <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            <polyline points="15 6 9 12 15 18" />
          </svg>
        </button>
        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 17, fontWeight: 700, color: 'var(--ink)' }}>
          Профиль
        </div>
      </div>

      {/* Content */}
      <div style={{ flex: 1, padding: '16px 20px 40px', overflowY: 'auto' }}>
        {loading ? (
          <div style={{ padding: '48px 0', textAlign: 'center', color: 'var(--ink-3)', fontFamily: 'Inter, sans-serif', fontSize: 13 }}>
            Загрузка...
          </div>
        ) : error || !session ? (
          <div style={{ padding: '48px 0', textAlign: 'center', color: 'var(--shutter)', fontSize: 14 }}>
            {error ?? 'Профиль недоступен'}
          </div>
        ) : (
          <>
            {/* Avatar row */}
            <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
              <button
                onClick={handlePickFile}
                disabled={uploading}
                style={{
                  position: 'relative', width: 72, height: 72, borderRadius: '50%',
                  background: session.avatar_url ? undefined : 'var(--paper-2)',
                  backgroundImage: session.avatar_url ? `url(${session.avatar_url})` : undefined,
                  backgroundSize: 'cover', backgroundPosition: 'center',
                  border: '1.5px solid rgba(201,136,30,.3)',
                  cursor: uploading ? 'not-allowed' : 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  flexShrink: 0, padding: 0,
                }}
              >
                {!session.avatar_url && (
                  <span style={{ fontFamily: 'Fraunces, serif', fontSize: 30, fontWeight: 600, color: 'var(--amber)' }}>
                    {initialFromName(session.name)}
                  </span>
                )}
                {uploading && (
                  <div style={{
                    position: 'absolute', inset: 0, borderRadius: '50%',
                    background: 'rgba(0,0,0,.55)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: 'var(--amber)', fontFamily: 'Inter, sans-serif', fontSize: 10,
                    letterSpacing: '.14em',
                  }}>
                    ...
                  </div>
                )}
                {!uploading && (
                  <span style={{
                    position: 'absolute', right: 0, bottom: 0,
                    width: 24, height: 24, borderRadius: '50%',
                    background: 'var(--amber)', border: '2px solid var(--paper)',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    color: '#fff',
                  }}>
                    <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M3 7h4l2-3h6l2 3h4v13H3z" /><circle cx="12" cy="13" r="4" />
                    </svg>
                  </span>
                )}
              </button>
              <div style={{ display: 'flex', flexDirection: 'column', gap: 6, minWidth: 0 }}>
                <span style={{
                  padding: '4px 10px', borderRadius: 8,
                  background: 'rgba(201,136,30,.12)',
                  fontFamily: 'Inter, sans-serif', fontSize: 10,
                  letterSpacing: '.16em', color: 'var(--amber)',
                  textTransform: 'uppercase', alignSelf: 'flex-start',
                }}>
                  Гость
                </span>
                <button
                  onClick={handlePickFile}
                  disabled={uploading}
                  style={{
                    background: 'none', border: 'none', padding: 0, cursor: 'pointer',
                    fontFamily: 'Inter, sans-serif', fontSize: 13, fontWeight: 600,
                    color: 'var(--amber)', textAlign: 'left',
                  }}
                >
                  {session.avatar_url ? 'Изменить фото' : 'Добавить фото'}
                </button>
              </div>
              <input
                ref={fileRef}
                type="file"
                accept="image/*"
                onChange={handleFileChange}
                style={{ display: 'none' }}
              />
            </div>

            {/* Name */}
            <div style={{ marginTop: 22 }}>
              <h2 style={{
                fontFamily: 'Fraunces, serif', fontStyle: 'italic',
                fontSize: 32, fontWeight: 500, letterSpacing: '-.02em',
                margin: 0, color: 'var(--ink)', lineHeight: 1.05,
                wordBreak: 'break-word',
              }}>
                {session.name}
              </h2>
              <div style={{ fontSize: 14, color: 'var(--ink-3)', marginTop: 6 }}>
                {session.event_title}
              </div>
              <div style={{
                fontFamily: 'Inter, sans-serif', fontSize: 10,
                letterSpacing: '.12em', color: 'var(--ink-4)',
                textTransform: 'uppercase', marginTop: 4,
              }}>
                {session.frames_used} из {session.frames_used + session.frames_remaining} кадров снято
              </div>
            </div>

            {/* Actions */}
            <div style={{ marginTop: 28, borderTop: '1px solid var(--line)' }}>
              <button
                onClick={openRename}
                style={{
                  width: '100%', padding: '16px 4px', display: 'flex', alignItems: 'center',
                  gap: 14, background: 'none', border: 'none', cursor: 'pointer',
                  borderBottom: '1px solid var(--line)', textAlign: 'left',
                }}
              >
                <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="var(--ink-2)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
                  <path d="M11 4H4v16h16v-7" />
                  <path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z" />
                </svg>
                <span style={{ flex: 1, fontFamily: 'Inter, sans-serif', fontSize: 15, color: 'var(--ink)' }}>
                  Изменить имя
                </span>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--ink-4)" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                  <polyline points="9 6 15 12 9 18" />
                </svg>
              </button>
            </div>
          </>
        )}
      </div>

      {/* Rename sheet */}
      {renaming && (
        <div
          onClick={() => !renameSaving && setRenaming(false)}
          style={{
            position: 'fixed', inset: 0, zIndex: 200,
            background: 'rgba(0,0,0,.35)',
            display: 'flex', alignItems: 'flex-end', justifyContent: 'center',
          }}
        >
          <div
            onClick={(e) => e.stopPropagation()}
            style={{
              width: '100%', maxWidth: 480,
              background: 'var(--paper)',
              borderTopLeftRadius: 20, borderTopRightRadius: 20,
              padding: '22px 20px calc(env(safe-area-inset-bottom, 16px) + 16px)',
            }}
          >
            <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 17, fontWeight: 700, color: 'var(--ink)' }}>
              Изменить имя
            </div>
            <div style={{ fontSize: 12, color: 'var(--ink-3)', marginTop: 4 }}>
              Только для этого события
            </div>
            <input
              autoFocus
              className="input-display"
              value={renameValue}
              onChange={(e) => setRenameValue(e.target.value)}
              onKeyDown={(e) => e.key === 'Enter' && saveRename()}
              maxLength={40}
              placeholder="Ваше имя"
              style={{ marginTop: 16 }}
            />
            <button
              className="btn"
              onClick={saveRename}
              disabled={renameSaving || !renameValue.trim()}
              style={{ marginTop: 12 }}
            >
              {renameSaving ? 'Сохраняем...' : 'Сохранить'}
            </button>
          </div>
        </div>
      )}

      {/* Toast */}
      {toast && (
        <div style={{
          position: 'fixed', bottom: 32, left: '50%', transform: 'translateX(-50%)',
          zIndex: 300,
          padding: '10px 18px', borderRadius: 999,
          background: 'var(--ink)', color: 'var(--paper)',
          fontFamily: 'Inter, sans-serif', fontSize: 13,
          boxShadow: '0 6px 16px rgba(0,0,0,.2)',
        }}>
          {toast}
        </div>
      )}
    </div>
  )
}

