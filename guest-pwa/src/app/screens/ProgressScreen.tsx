import { Link, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { useEvent } from '../queries'
import { CenterSpinner, ErrorBox, TopBar } from '../ui'

export default function ProgressScreen() {
  const { id = '' } = useParams()
  const event = useEvent(id)
  const album = useQuery({
    queryKey: ['progress-album', id],
    refetchInterval: 20_000,
    queryFn: async () => (await hostApi.get<Schemas['AlbumOut']>(`/events/${id}/album`, { params: { limit: 24 } })).data,
  })

  if (event.isLoading) return (<><TopBar back={`/app/events/${id}`} title="Ход съёмки" /><CenterSpinner /></>)
  if (event.error || !event.data) return (<><TopBar back="/app" title="Ход съёмки" /><main className="host-main"><ErrorBox message={apiErrorMessage(event.error)} /></main></>)

  const e = event.data
  const s = e.settings
  const potential = Math.max(1, e.guests_count * s.frames_per_guest)
  const pct = Math.min(100, Math.round((e.frames_count / potential) * 100))
  const frames = album.data?.items ?? []
  const guests = useQuery({
    queryKey: ['event-guests', id],
    refetchInterval: 20_000,
    queryFn: async () => (await hostApi.get<Schemas['GuestProgressOut'][]>(`/events/${id}/guests`)).data,
  })

  return (
    <>
      <TopBar back={`/app/events/${id}`} title="Ход съёмки" kicker={e.title} />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 16 }}>
        <div className="host-card" style={{ padding: 16 }}>
          <div style={{ display: 'flex' }}>
            {([[e.guests_count, `из ${s.max_guests} гостей`], [e.frames_count, 'кадров снято'], [s.frames_per_guest, 'кадров на гостя']] as const).map(([v, l]) => (
              <div key={l} style={{ flex: 1, textAlign: 'center' }}>
                <div className="host-mono" style={{ fontSize: 28 }}>{v}</div>
                <div className="host-edge" style={{ fontSize: 11 }}>{l}</div>
              </div>
            ))}
          </div>
          <div style={{ marginTop: 16 }}>
            <div className="host-edge" style={{ display: 'flex', justifyContent: 'space-between', marginBottom: 6 }}>
              <span>Плёнка израсходована</span><span>{pct}%</span>
            </div>
            <div style={{ height: 8, borderRadius: 4, overflow: 'hidden', background: 'var(--paper-3)' }}>
              <div style={{ width: `${pct}%`, height: '100%', background: 'var(--amber)' }} />
            </div>
          </div>
        </div>

        <div>
          <div className="host-field-label" style={{ margin: '0 2px 8px' }}>Гости</div>
          {guests.isLoading && <CenterSpinner />}
          {guests.data && guests.data.length === 0 && <p className="host-muted">Пока никто не вошёл. Покажите гостям QR-код.</p>}
          {guests.data && guests.data.length > 0 && (
            <div className="host-card">
              {guests.data.map((g) => {
                const pct = Math.min(100, Math.round((g.frames_count / Math.max(1, g.frames_per_guest)) * 100))
                return (
                  <div key={g.id} className="host-row" style={{ cursor: 'default' }}>
                    <span style={{ width: 40, height: 40, borderRadius: '50%', background: 'var(--paper-2)', overflow: 'hidden', flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', fontWeight: 700, color: 'var(--ink-3)' }}>
                      {g.avatar_url ? <img src={g.avatar_url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : g.name.slice(0, 1).toUpperCase()}
                    </span>
                    <span style={{ flex: 1, minWidth: 0 }}>
                      <span style={{ display: 'block', fontWeight: 600 }}>{g.name}{g.is_owner ? ' (вы)' : ''}</span>
                      <span style={{ display: 'block', height: 6, borderRadius: 3, background: 'var(--paper-3)', marginTop: 6, overflow: 'hidden' }}>
                        <span style={{ display: 'block', width: `${pct}%`, height: '100%', background: 'var(--amber)' }} />
                      </span>
                    </span>
                    <span className="host-mono" style={{ fontSize: 14 }}>{g.frames_count}/{g.frames_per_guest}</span>
                  </div>
                )
              })}
            </div>
          )}
        </div>

        <div>
          <div className="host-field-label" style={{ margin: '0 2px 8px' }}>Последние кадры</div>
          {album.isLoading && <CenterSpinner />}
          {frames.length === 0 && !album.isLoading && <p className="host-muted">Пока ни одного кадра.</p>}
          <div style={{ display: 'grid', gap: 6, gridTemplateColumns: 'repeat(auto-fill, minmax(96px, 1fr))' }}>
            {frames.map((f) => (
              <Link key={f.id} to={`/app/events/${id}/album?f=${f.id}`} style={{ aspectRatio: '1', overflow: 'hidden', borderRadius: 12, display: 'block' }}>
                <img src={f.thumbnail_url ?? f.preview_url ?? f.full_url} alt="" loading="lazy" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block' }} />
              </Link>
            ))}
          </div>
        </div>
      </main>
    </>
  )
}
