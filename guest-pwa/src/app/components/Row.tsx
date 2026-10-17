import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { Icon, icons } from '../ui'

export function Row({ icon, label, hint, to, onClick, danger, value }: {
  icon?: string | ReactNode; label: string; hint?: string; to?: string; onClick?: () => void; danger?: boolean; value?: string
}) {
  const inner = (
    <>
      {icon && <span style={{ color: danger ? 'var(--shutter)' : 'var(--amber)', display: 'flex' }}>{typeof icon === 'string' ? <Icon d={icon} size={20} /> : icon}</span>}
      <span style={{ flex: 1, color: danger ? 'var(--shutter)' : 'inherit' }}>
        {label}
        {hint && <span className="host-muted" style={{ display: 'block', fontSize: 12, marginTop: 1 }}>{hint}</span>}
      </span>
      {value && <span className="host-mono" style={{ color: 'var(--ink-3)', fontSize: 13 }}>{value}</span>}
      <span style={{ color: 'var(--ink-4)', display: 'flex' }}><Icon d={icons.chevron} size={18} /></span>
    </>
  )
  return to
    ? <Link to={to} className="host-row">{inner}</Link>
    : <button className="host-row" onClick={onClick}>{inner}</button>
}
