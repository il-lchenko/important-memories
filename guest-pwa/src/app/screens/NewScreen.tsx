import { Link } from 'react-router-dom'
import { useEntitlements } from '../queries'
import { BrandIcon, TopBar } from '../ui'

function Choice({ to, icon, title, text, meta }: { to: string; icon: 'event' | 'solo' | 'mini'; title: string; text: string; meta?: string }) {
  return (
    <Link to={to} className="host-card" style={{ display: 'flex', gap: 16, alignItems: 'flex-start', padding: 18, textDecoration: 'none', color: 'inherit' }}>
      <span style={{ width: 48, height: 48, borderRadius: 16, background: 'var(--paper-2)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <BrandIcon name={icon} size={34} />
      </span>
      <span style={{ flex: 1 }}>
        <span className="host-h2" style={{ display: 'block', fontSize: 20 }}>{title}</span>
        <span className="host-muted" style={{ display: 'block', marginTop: 4 }}>{text}</span>
        {meta && <span className="host-edge" style={{ display: 'block', marginTop: 10, color: 'var(--amber-2)' }}>{meta}</span>}
      </span>
    </Link>
  )
}

/** Что создаём: событие с гостями, личное соло-альбом или подборку кадров. */
export default function NewScreen() {
  const ent = useEntitlements().data
  const eventsMeta = ent && ent.free_events_left !== null && ent.free_events_left !== undefined
    ? `бесплатных событий в этом месяце: ${ent.free_events_left}`
    : undefined
  const soloMeta = ent ? `кадров осталось в этом месяце: ${ent.solo_frames_left}` : undefined
  const miniMeta = ent
    ? ent.mini_albums_limit === null ? 'подборок без ограничений' : `бесплатно до ${ent.mini_albums_limit} подборок`
    : undefined
  return (
    <>
      <TopBar back="/app" title="Новый альбом" />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 16 }}>
        <Choice to="/app/events/new" icon="event" title="Событие с гостями"
          text="Свадьба, день рождения, корпоратив. Гости снимают по QR-коду, все кадры собираются в одном альбоме."
          meta={eventsMeta} />
        <Choice to="/app/solo/new" icon="solo" title="Соло-альбом"
          text="Личный альбом без гостей: путешествие, отпуск, дневник. Снимаете сами на плёночную камеру."
          meta={soloMeta} />
        <Choice to="/app/collections/new" icon="mini" title="Мини-альбом"
          text="Подборка лучших кадров из всех ваших альбомов. Файлы не копируются, поэтому хранилище не растёт."
          meta={miniMeta} />
      </main>
    </>
  )
}
