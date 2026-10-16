import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { EVENT_TYPE_LABELS, formatShortDate } from '../format'
import { useCollections } from '../queries'
import { CenterSpinner, ErrorBox, Icon, icons, TopBar } from '../ui'

type Block = Schemas['MemoryBlock']

function BlockCard({ b }: { b: Block }) {
  const target = b.event_id ?? b.event_ids[0]
  const thumbs = b.thumbs.slice(0, b.kind === 'single' ? 1 : 4)
  const body = (
    <>
      <div style={{ display: 'grid', gap: 2, gridTemplateColumns: thumbs.length > 1 ? '1fr 1fr' : '1fr', background: 'var(--ink)', borderBottom: '1px solid var(--ink)' }}>
        {thumbs.map((t) => (
          <div key={t.frame_id} style={{ aspectRatio: thumbs.length > 1 ? '1' : '4 / 3', overflow: 'hidden', background: '#1A1714' }}>
            <img src={t.url} alt="" loading="lazy" style={{ width: '100%', height: '100%', objectFit: 'cover', display: 'block', transform: t.rotation ? `rotate(${t.rotation}deg) scale(${t.rotation % 180 ? 1.34 : 1})` : undefined }} />
          </div>
        ))}
        {thumbs.length === 0 && <div style={{ aspectRatio: '4 / 3' }} />}
      </div>
      <div style={{ padding: '12px 16px 16px' }}>
        <div className="host-edge">
          {b.kind === 'collection' ? `подборка ▸ ${b.albums_count ?? b.event_ids.length} альбомов` : (b.event_type ? EVENT_TYPE_LABELS[b.event_type] ?? 'Событие' : 'Событие')}
          {b.date_iso ? ` ▸ ${formatShortDate(b.date_iso)}` : ''}
        </div>
        <div className="host-frame-title">{b.title}</div>
      </div>
    </>
  )
  return target
    ? <Link to={`/app/events/${target}/album`} className="host-card" style={{ display: 'block', textDecoration: 'none', color: 'inherit', overflow: 'hidden' }}>{body}</Link>
    : <div className="host-card" style={{ overflow: 'hidden' }}>{body}</div>
}

export default function MemoriesScreen() {
  const q = useQuery({
    queryKey: ['memories'],
    queryFn: async () => (await hostApi.get<Schemas['MemoriesOut']>('/memories/')).data,
  })
  const minis = useCollections().data
  return (
    <>
      <TopBar title="Кадры" kicker="Воспоминания" right={<Link to="/app/collections/new" className="host-icon-btn" aria-label="Новая подборка"><Icon d={icons.plus} /></Link>} />
      <main className="host-main" style={{ paddingTop: 16 }}>
        {minis && minis.collections.length > 0 && (
          <div style={{ marginBottom: 22 }}>
            <div className="host-field-label" style={{ margin: '0 2px 8px' }}>Мини-альбомы</div>
            <div className="host-grid">
              {minis.collections.map((c) => (
                <Link key={c.id} to={`/app/collections/${c.id}`} className="host-card" style={{ display: 'block', textDecoration: 'none', color: 'inherit', overflow: 'hidden' }}>
                  <div style={{ display: 'grid', gap: 2, gridTemplateColumns: c.preview_urls.length > 1 ? '1fr 1fr' : '1fr', background: 'var(--ink)', borderBottom: '1px solid var(--ink)' }}>
                    {c.preview_urls.slice(0, 4).map((u) => <img key={u} src={u} alt="" loading="lazy" style={{ width: '100%', aspectRatio: '1', objectFit: 'cover', display: 'block' }} />)}
                    {c.preview_urls.length === 0 && <div style={{ aspectRatio: '4 / 3' }} />}
                  </div>
                  <div style={{ padding: '12px 16px 16px' }}>
                    <div className="host-edge">подборка ▸ {c.items_count} кадр.</div>
                    <div className="host-frame-title">{c.title}</div>
                  </div>
                </Link>
              ))}
            </div>
          </div>
        )}
        <div className="host-field-label" style={{ margin: '0 2px 8px' }}>Подборки по событиям</div>
        {q.isLoading && <CenterSpinner />}
        {q.error && <ErrorBox message={apiErrorMessage(q.error)} onRetry={() => void q.refetch()} />}
        {q.data && q.data.blocks.length === 0 && (
          <div className="host-card" style={{ padding: 28, textAlign: 'center' }}>
            <h2 className="host-h2" style={{ marginBottom: 8 }}>Здесь появятся лучшие кадры</h2>
            <p className="host-muted">Когда в ваших альбомах будут фотографии, мы соберём из них подборки.</p>
          </div>
        )}
        <div className="host-grid">
          {q.data?.blocks.map((b, i) => <BlockCard key={`${b.title}-${i}`} b={b} />)}
        </div>
      </main>
    </>
  )
}
