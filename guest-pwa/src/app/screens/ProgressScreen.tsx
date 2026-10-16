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
