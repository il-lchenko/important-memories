import { NavLink, Navigate, Outlet, useLocation, useNavigate } from 'react-router-dom'
import { hostTokens } from './api/hostClient'
import { Icon, icons, ToastHost } from './ui'

export function RequireHost({ children }: { children: React.ReactNode }) {
  const location = useLocation()
  if (!hostTokens.isLoggedIn()) {
    const next = location.pathname + location.search
    return <Navigate to={`/app/login?next=${encodeURIComponent(next)}`} replace />
  }
  return <>{children}</>
}

const TABS = [
  { to: '/app', label: 'Альбомы', icon: icons.albums, end: true },
  { to: '/app/memories', label: 'Кадры', icon: icons.frames, end: false },
  { to: '/app/profile', label: 'Профиль', icon: icons.profile, end: false },
]

/** Экраны с нижней навигацией (вкладки). Внутренние экраны события — без неё. */
export function TabsShell() {
  const navigate = useNavigate()
  return (
    <div className="host-root">
      <nav className="host-sidebar" aria-label="Разделы">
        <div style={{ fontFamily: 'Playfair Display, serif', fontWeight: 700, fontSize: 22, margin: '0 12px 24px' }}>
          Impo<span style={{ color: 'var(--amber)' }}>Mento</span>
        </div>
        {TABS.map((t) => (
          <NavLink key={t.to} to={t.to} end={t.end}>
            <Icon d={t.icon} size={18} /> {t.label}
          </NavLink>
        ))}
        <button className="btn btn-sm" style={{ marginTop: 16 }} onClick={() => navigate('/app/events/new')}>
          <Icon d={icons.plus} size={18} /> Новый альбом
        </button>
      </nav>
      <div className="host-with-sidebar">
        <Outlet />
      </div>
      <nav className="host-tabbar" aria-label="Разделы">
        <NavLink to={TABS[0].to} end className="host-tab"><Icon d={TABS[0].icon} />{TABS[0].label}</NavLink>
        <NavLink to={TABS[1].to} className="host-tab"><Icon d={TABS[1].icon} />{TABS[1].label}</NavLink>
        <div style={{ flex: 1, display: 'flex', justifyContent: 'center' }}>
          <button className="host-fab" aria-label="Новый альбом" onClick={() => navigate('/app/events/new')}>
            <Icon d={icons.plus} size={26} stroke={2.2} />
          </button>
        </div>
        <NavLink to={TABS[2].to} className="host-tab"><Icon d={TABS[2].icon} />{TABS[2].label}</NavLink>
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
