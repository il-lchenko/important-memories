import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { MemoryBlockView } from '../components/MemoryBlockView'
import { useCollections } from '../queries'
import { CenterSpinner, ErrorBox, Icon, icons, TopBar } from '../ui'

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
                  <div style={{ display: 'grid', gap: 2, gridTemplateColumns: !c.cover_url && c.preview_urls.length > 1 ? '1fr 1fr' : '1fr', background: 'var(--ink)', borderBottom: '1px solid var(--line)' }}>
                    {(c.cover_url ? [c.cover_url] : c.preview_urls.slice(0, 4)).map((u) => <img key={u} src={u} alt="" loading="lazy" style={{ width: '100%', aspectRatio: '1', objectFit: 'cover', display: 'block' }} />)}
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
        <div style={{ display: 'flex', flexDirection: 'column', gap: 28 }}>
          {q.data?.blocks.map((b, i) => <MemoryBlockView key={`${b.title}-${i}`} b={b} />)}
        </div>
      </main>
    </>
  )
}
