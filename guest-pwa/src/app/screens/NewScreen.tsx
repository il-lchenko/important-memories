import { Link } from 'react-router-dom'
import { useEntitlements } from '../queries'
import { TopBar } from '../ui'

function Choice({ to, no, title, text, meta }: { to: string; no: string; title: string; text: string; meta?: string }) {
  return (
    <Link to={to} className="host-card" style={{ display: 'block', textDecoration: 'none', color: 'inherit', overflow: 'hidden' }}>
      <div className="host-cover" style={{ aspectRatio: '16 / 5' }}>
        <span className="host-frameno">{no}</span>
      </div>
      <div style={{ padding: '12px 16px 16px' }}>
        <div className="host-frame-title" style={{ margin: 0 }}>{title}</div>
        <p className="host-muted" style={{ margin: '4px 0 0' }}>{text}</p>
        {meta && <div className="host-edge" style={{ marginTop: 8 }}>{meta}</div>}
      </div>
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
      <TopBar back="/app" title="Новый альбом" kicker="Что снимаем" />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 16 }}>
        <Choice to="/app/events/new" no="01" title="Событие с гостями"
          text="Свадьба, день рождения, корпоратив. Гости снимают по QR-коду, все кадры собираются в одном альбоме."
          meta={eventsMeta} />
        <Choice to="/app/solo/new" no="02" title="Соло-альбом"
          text="Личный альбом без гостей: путешествие, отпуск, дневник. Снимаете сами на плёночную камеру."
          meta={soloMeta} />
        <Choice to="/app/collections/new" no="03" title="Мини-альбом"
          text="Подборка лучших кадров из всех ваших альбомов. Файлы не копируются, поэтому хранилище не растёт."
          meta={miniMeta} />
      </main>
    </>
  )
}
