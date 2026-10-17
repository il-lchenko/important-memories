import { NavLink, Navigate, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { hostTokens } from './api/hostClient'
import { AlbumPlusIcon, Icon, icons, ToastHost } from './ui'

export function RequireHost({ children }: { children: React.ReactNode }) {
  const location = useLocation()
  if (!hostTokens.isLoggedIn()) {
    const next = location.pathname + location.search
    return <Navigate to={`/app/login?next=${encodeURIComponent(next)}`} replace />
  }
  return <>{children}</>
}

const TABS = [
  { to: '/app', label: 'Альбомы', icon: icons.albums, iconOn: icons.albumsOn, end: true, tour: undefined as string | undefined },
  { to: '/app/memories', label: 'Кадры', icon: icons.frames, iconOn: icons.framesOn, end: false, tour: 'tab-frames' },
  { to: '/app/profile', label: 'Профиль', icon: icons.profile, iconOn: icons.profileOn, end: false, tour: 'tab-profile' },
]

/** Экраны с нижней навигацией (вкладки). Внутренние экраны события — без неё. */
export function TabsShell() {
  const navigate = useNavigate()
  const { pathname } = useLocation()
  const onAlbums = pathname === '/app' || pathname === '/app/'
  return (
    <div className="host-root">
      <nav className="host-sidebar" aria-label="Разделы">
        <div style={{ fontFamily: 'Playfair Display, serif', fontWeight: 700, fontSize: 22, margin: '0 12px 24px' }}>
          Impo<span style={{ color: 'var(--amber)' }}>Mento</span>
        </div>
        {TABS.map((t) => (
          <NavLink key={t.to} to={t.to} end={t.end} data-tour={t.tour}>
            {({ isActive }) => (<><Icon d={isActive ? t.iconOn : t.icon} size={22} /> {t.label}</>)}
          </NavLink>
        ))}
        <button className="btn btn-sm" style={{ marginTop: 16 }} data-tour="new" onClick={() => navigate('/app/new')}>
          <AlbumPlusIcon size={22} /> Новый альбом
        </button>
      </nav>
      <div className="host-with-sidebar">
        <Outlet />
      </div>
      {onAlbums && (
        <button className="host-fab" aria-label="Новый альбом" data-tour="new" onClick={() => navigate('/app/new')}>
          <AlbumPlusIcon size={34} />
        </button>
      )}
      <nav className="host-tabbar" aria-label="Разделы">
        {TABS.map((t) => (
          <NavLink key={t.to} to={t.to} end={t.end} className="host-tab" data-tour={t.tour}>
            {({ isActive }) => (
              <>
                <span className="host-tab-dot" data-on={isActive} />
                <Icon d={isActive ? t.iconOn : t.icon} size={24} />
                <span className="host-tab-label">{t.label}</span>
              </>
            )}
          </NavLink>
        ))}
      </nav>
      <ToastHost />
    </div>
  )
}

/** Внутренние экраны (событие, QR, настройки): без вкладок, свой TopBar. */
export function PlainShell() {
  return (
    <div className="host-root">
      <Outlet />
      <ToastHost />
    </div>
  )
}
