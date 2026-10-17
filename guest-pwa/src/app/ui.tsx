import { useEffect, useState, type CSSProperties, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import { brandIcons, materialPaths } from './iconData'

export function Icon({ d, size = 20 }: { d: string; size?: number; stroke?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="currentColor" aria-hidden="true" style={{ flexShrink: 0 }}>
      <path d={d} />
    </svg>
  )
}

/** Фирменный значок ImpoMento: ink-штрихи плюс янтарная искра. */
export function BrandIcon({ name, size = 24, stroke = 1.6 }: { name: keyof typeof brandIcons; size?: number; stroke?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true" style={{ flexShrink: 0 }}>
      {brandIcons[name].map((l, i) => {
        if (l.kind === 'accent') return <path key={i} d={l.d} fill="var(--amber)" />
        if (l.kind === 'ink') return <path key={i} d={l.d} fill="var(--ink)" />
        return <path key={i} d={l.d} stroke="var(--ink)" strokeOpacity={l.kind === 'soft' ? 0.3 : 1} strokeWidth={stroke} />
      })}
    </svg>
  )
}

/** Маркер списков: маленькая янтарная искра. */
export function Spark({ size = 16 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true" style={{ flexShrink: 0 }}>
      <path d="M12 2Q14 10 22 12Q14 14 12 22Q10 14 2 12Q10 10 12 2Z" fill="var(--amber)" />
    </svg>
  )
}

/** Кнопка «новый альбом»: значок «Альбомы» с плюсом в круге (на янтарном фоне). */
export function AlbumPlusIcon({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" aria-hidden="true">
      <path d={materialPaths.auto_stories} fill="#fff" transform="translate(-1.2 -1.6) scale(1.02)" />
      <circle cx="18.6" cy="18.6" r="5.7" fill="var(--amber)" />
      <circle cx="18.6" cy="18.6" r="4.5" fill="#fff" />
      <path d="M18.6 16.3v4.6M16.3 18.6h4.6" stroke="var(--amber)" strokeWidth="1.6" strokeLinecap="round" />
    </svg>
  )
}

/** Значки взяты из шрифта Material, как в приложении (Flutter Icons.*). */
export const icons = {
  back: materialPaths.chevron_left,
  close: materialPaths.close,
  plus: materialPaths.add,
  albums: materialPaths.auto_stories_outlined,
  albumsOn: materialPaths.auto_stories,
  frames: materialPaths.camera_roll_outlined,
  framesOn: materialPaths.camera_roll,
  profile: materialPaths.account_circle_outlined,
  profileOn: materialPaths.account_circle,
  person: materialPaths.person_outline,
  search: materialPaths.search,
  qr: materialPaths.qr_code_2,
  share: materialPaths.ios_share,
  copy: materialPaths.copy_outlined,
  settings: materialPaths.tune_outlined,
  chevron: materialPaths.chevron_right,
  roll: materialPaths.camera_roll_outlined,
  calendar: materialPaths.calendar_today_outlined,
  camera: materialPaths.camera_alt_outlined,
  users: materialPaths.people_outline,
  download: materialPaths.download_outlined,
  trash: materialPaths.delete_outline,
  mail: materialPaths.mail_outline,
  lock: materialPaths.lock_open_outlined,
  link: materialPaths.link,
  logout: materialPaths.logout,
  rotate: materialPaths.rotate_right,
  addPhoto: materialPaths.add_photo_alternate_outlined,
}

export function Spinner({ style }: { style?: CSSProperties }) {
  return <div className="host-spinner" style={style} role="status" aria-label="Загрузка" />
}

export function CenterSpinner() {
  return (
    <div style={{ display: 'flex', justifyContent: 'center', padding: '64px 0' }}>
      <Spinner />
    </div>
  )
}

export function ErrorBox({ message, onRetry }: { message: string; onRetry?: () => void }) {
  return (
    <div className="host-card" style={{ padding: 18, margin: '16px 0', textAlign: 'center' }}>
      <div style={{ color: 'var(--shutter)', fontSize: 14, marginBottom: onRetry ? 12 : 0 }}>{message}</div>
      {onRetry && (
        <button className="btn-ghost btn-sm" style={{ maxWidth: 220, margin: '0 auto' }} onClick={onRetry}>
          Повторить
        </button>
      )}
    </div>
  )
}

export function TopBar({ title, kicker, back, right }: {
  title?: ReactNode; kicker?: string; back?: string | true; right?: ReactNode
}) {
  const navigate = useNavigate()
  return (
    <header className="host-header">
      <div className="host-header-inner">
        {back && (
          <button
            className="host-icon-btn"
            aria-label="Назад"
            onClick={() => (back === true ? navigate(-1) : navigate(back))}
          >
            <Icon d={icons.back} />
          </button>
        )}
        <div style={{ flex: 1, minWidth: 0 }}>
          {kicker && <div className="host-kicker">{kicker}</div>}
          {title && (
            <h1 className={back ? 'host-h2' : 'host-title'}
              style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
              {title}
            </h1>
          )}
        </div>
        {right}
      </div>
    </header>
  )
}

export function Sheet({ open, onClose, title, children }: {
  open: boolean; onClose: () => void; title?: ReactNode; children: ReactNode
}) {
  useEffect(() => {
    if (!open) return
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [open, onClose])
  if (!open) return null
  return (
    <div className="host-sheet-backdrop" onClick={onClose}>
      <div className="host-sheet" role="dialog" aria-modal="true" onClick={(e) => e.stopPropagation()}>
        <div className="host-sheet-handle" />
        {title && <h2 className="host-h2" style={{ marginBottom: 14 }}>{title}</h2>}
        {children}
      </div>
    </div>
  )
}

let toastListener: ((msg: string) => void) | null = null

export function toast(message: string) {
  toastListener?.(message)
}

export function ToastHost() {
  const [message, setMessage] = useState<string | null>(null)
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout> | undefined
    toastListener = (msg) => {
      setMessage(msg)
      clearTimeout(timer)
      timer = setTimeout(() => setMessage(null), 2600)
    }
    return () => { toastListener = null; clearTimeout(timer) }
  }, [])
  if (!message) return null
  return <div className="host-toast" role="status">{message}</div>
}

export async function copyText(text: string, okMessage = 'Скопировано') {
  try {
    await navigator.clipboard.writeText(text)
    toast(okMessage)
  } catch {
    window.prompt('Скопируйте вручную', text)
  }
}

export async function shareLink(url: string, title?: string) {
  if (navigator.share) {
    try {
      await navigator.share({ url, title })
      return
    } catch (e) {
      if ((e as DOMException)?.name === 'AbortError') return
    }
  }
  await copyText(url, 'Ссылка скопирована')
}
