import { useEffect, useState, type CSSProperties, type ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'

export function Icon({ d, size = 20, stroke = 1.8 }: { d: string; size?: number; stroke?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor"
      strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  )
}

export const icons = {
  back: 'M15 18l-6-6 6-6',
  close: 'M18 6 6 18M6 6l12 12',
  plus: 'M12 5v14M5 12h14',
  albums: 'M4 5h16v14H4zM4 15l4-4 4 4 3-3 5 5',
  frames: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h7v7h-7z',
  profile: 'M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4 21a8 8 0 0 1 16 0',
  search: 'M11 19a8 8 0 1 0 0-16 8 8 0 0 0 0 16zM21 21l-4.3-4.3',
  qr: 'M3 3h7v7H3zM14 3h7v7h-7zM3 14h7v7H3zM14 14h3v3h-3zM20 14v.01M14 20v.01M17 17h4v4',
  share: 'M4 12v7a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-7M16 6l-4-4-4 4M12 2v13',
  copy: 'M9 9h11v11H9zM5 15H4V4h11v1',
  settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  chevron: 'M9 18l6-6-6-6',
  roll: 'M3 7h18v12H3zM3 11h18M7 7v12M17 7v12',
  calendar: 'M4 6h16v14H4zM4 10h16M8 3v4M16 3v4',
  camera: 'M23 19a2 2 0 0 1-2 2H3a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h4l2-3h6l2 3h4a2 2 0 0 1 2 2zM12 17a4 4 0 1 0 0-8 4 4 0 0 0 0 8z',
  users: 'M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2M9 11a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM23 21v-2a4 4 0 0 0-3-3.9M16 3.1a4 4 0 0 1 0 7.8',
  download: 'M12 4v12M6 12l6 6 6-6M4 21h16',
  trash: 'M3 6h18M8 6V4h8v2M19 6l-1 14H6L5 6',
  mail: 'M4 4h16v16H4zM4 6l8 7 8-7',
  lock: 'M5 11h14v10H5zM8 11V7a4 4 0 0 1 8 0v4',
  link: 'M10 13a5 5 0 0 0 7.5.5l3-3a5 5 0 0 0-7-7l-1.7 1.7M14 11a5 5 0 0 0-7.5-.5l-3 3a5 5 0 0 0 7 7l1.7-1.7',
  logout: 'M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9',
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
