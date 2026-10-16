import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'

/** Карточка альбома как в приложении: снимок на всю карточку, статус сверху, название и цифры снизу. */
export function PhotoCard({ to, cover, covers, badge, title, meta, ariaLabel }: {
  to: string
  cover?: string | null
  /** Несколько превью (подборки): мозаика вместо одной обложки. */
  covers?: string[]
  badge?: ReactNode
  title: string
  meta?: ReactNode
  ariaLabel?: string
}) {
  return (
    <Link to={to} className="host-photo" aria-label={ariaLabel ?? title}>
      {covers && covers.length > 0 ? (
        <div className="host-mosaic" style={{ gridTemplateColumns: covers.length > 1 ? '1fr 1fr' : '1fr' }}>
          {covers.slice(0, 4).map((u) => <img key={u} src={u} alt="" loading="lazy" />)}
        </div>
      ) : cover ? (
        <img src={cover} alt="" loading="lazy" />
      ) : null}
      {badge && <div className="host-photo-top">{badge}</div>}
      <div className="host-photo-bottom">
        <div className="host-photo-title">{title}</div>
        {meta && <div className="host-photo-meta">{meta}</div>}
      </div>
    </Link>
  )
}
