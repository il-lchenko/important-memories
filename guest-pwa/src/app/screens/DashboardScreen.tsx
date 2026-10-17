import { AlbumsTour } from '../tours'
import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import type { EventOut, InvitedEventOut, Schemas } from '../api/hostClient'
import { apiErrorMessage } from '../api/hostClient'
import { PhotoCard } from '../components/PhotoCard'
import { STATUS_META } from '../format'
import { useCollections, useEvents, useInvitedEvents, useMe } from '../queries'
import { CenterSpinner, ErrorBox, Icon, icons, TopBar } from '../ui'

type Scope = 'mine' | 'solo' | 'minis' | 'invited' | 'all'
type StatusFilter = 'all' | 'active' | 'completed'

type Card =
  | { kind: 'mine'; event: EventOut }
  | { kind: 'invited'; event: InvitedEventOut }
  | { kind: 'mini'; col: Schemas['CollectionSummaryOut'] }

function StatusStamp({ status }: { status: string }) {
  const meta = STATUS_META[status] ?? STATUS_META.draft
  return <span className="host-badge" style={{ color: meta.color }}>{meta.label}</span>
}

function Meta({ guests, frames, date }: { guests?: number; frames: number; date?: string | null }) {
  return (
    <>
      {guests !== undefined && <span><Icon d={icons.person} size={16} />{guests}</span>}
      <span className="hot"><Icon d={icons.roll} size={16} />{frames}</span>
      {date && <span><Icon d={icons.calendar} size={16} />{date}</span>}
    </>
  )
}

const fullDate = (iso?: string | null) => {
  if (!iso) return null
  const d = new Date(iso)
  return `${String(d.getDate()).padStart(2, '0')}.${String(d.getMonth() + 1).padStart(2, '0')}.${d.getFullYear()}`
}

function EventCard({ card }: { card: Card }) {
  if (card.kind === 'mini') {
    const c = card.col
    return (
      <PhotoCard to={`/app/collections/${c.id}`} covers={c.preview_urls} title={c.title}
        badge={<span className="host-badge" style={{ color: '#C9881E' }}>Мини-альбом</span>}
        meta={<Meta frames={c.items_count} date={fullDate(c.created_at)} />} />
    )
  }
  const e = card.event
  const solo = card.kind === 'mine' && card.event.kind === 'solo'
  const to = card.kind === 'mine' ? `/app/events/${e.id}` : `/app/events/${e.id}/album`
  const badge = (
    <>
      {solo ? <span className="host-badge" style={{ color: '#C9881E' }}>Соло</span> : <StatusStamp status={e.status} />}
      {card.kind === 'invited' && <span className="host-badge" style={{ color: '#F0E8D8' }}>Гость</span>}
    </>
  )
  const meta = card.kind === 'mine'
    ? <Meta guests={solo ? undefined : card.event.guests_count ?? 0} frames={card.event.frames_count ?? 0} date={fullDate(e.start_at)} />
    : <Meta frames={card.event.my_frames_count} date={fullDate(e.start_at)} />
  return <PhotoCard to={to} cover={e.cover_url} badge={badge} title={e.title} meta={meta} />
}

export default function DashboardScreen() {
  const events = useEvents()
  const invited = useInvitedEvents()
  const collections = useCollections()
  const me = useMe()
  const [scope, setScope] = useState<Scope>('mine')
  const [status, setStatus] = useState<StatusFilter>('all')
  const [query, setQuery] = useState('')

  const cards = useMemo<Card[]>(() => {
    const q = query.trim().toLowerCase()
    const own = (events.data ?? []).filter((e) => e.status !== 'cancelled')
    const mine: Card[] = own.filter((e) => e.kind !== 'solo').map((event) => ({ kind: 'mine', event }))
    const solo: Card[] = own.filter((e) => e.kind === 'solo').map((event) => ({ kind: 'mine', event }))
    const inv: Card[] = (invited.data ?? []).map((event) => ({ kind: 'invited', event }))
    const minis: Card[] = (collections.data?.collections ?? []).map((col) => ({ kind: 'mini', col }))
    const list = scope === 'mine' ? mine : scope === 'solo' ? solo : scope === 'minis' ? minis : scope === 'invited' ? inv : [...mine, ...solo, ...minis, ...inv]
    const dateOf = (c: Card) => (c.kind === 'mini' ? c.col.created_at : c.event.start_at ?? '')
    return list
      .filter((c) => (c.kind === 'mini' || status === 'all' ? true : c.event.status === status))
      .filter((c) => (q ? (c.kind === 'mini' ? c.col.title : c.event.title).toLowerCase().includes(q) : true))
      .sort((a, b) => dateOf(b).localeCompare(dateOf(a)))
  }, [events.data, invited.data, collections.data, scope, status, query])

  const loading = events.isLoading || (scope === 'minis' && collections.isLoading) || (scope === 'invited' && invited.isLoading)
  const error = events.error ?? (scope === 'invited' ? invited.error : null) ?? (scope === 'minis' ? collections.error : null)
  const emptyTitle = query || status !== 'all' ? 'Ничего не нашлось'
    : scope === 'invited' ? 'Пока нет событий, где вы гость'
    : scope === 'solo' ? 'Заведите личный альбом'
    : scope === 'minis' ? 'Соберите первую подборку'
    : 'Создайте первый альбом'
  const emptyText = scope === 'solo' ? 'Соло-альбом для себя: путешествие, отпуск, дневник. Снимаете сами на плёночную камеру.'
    : scope === 'minis' ? 'Мини-альбом собирает лучшие кадры из ваших альбомов в одну подборку.'
    : 'Гости снимают на свои телефоны по QR-коду, а все кадры собираются в одном альбоме.'
  const newTo = scope === 'solo' ? '/app/solo/new' : scope === 'minis' ? '/app/collections/new' : '/app/events/new'

  return (
    <>
      <AlbumsTour ready={!loading && !error} />
      <TopBar title="Мои альбомы" kicker={me.data?.is_admin ? 'Админ-режим · платежи в обход' : undefined} />
      <main className="host-main">
        <div className="host-scroll-x" data-tour="filters" style={{ padding: '16px 0 10px' }}>
          {([['mine', 'События'], ['solo', 'Соло'], ['minis', 'Подборки'], ['invited', 'Я гость'], ['all', 'Все']] as const).map(([k, label]) => (
            <button key={k} className="host-chip" data-active={scope === k} onClick={() => setScope(k)}>{label}</button>
          ))}
          {scope !== 'minis' && (
            <>
              <span style={{ width: 1, background: 'var(--line)', margin: '4px 2px' }} />
              {([['all', 'Любой статус'], ['active', 'Идут'], ['completed', 'Завершены']] as const).map(([k, label]) => (
                <button key={k} className="host-chip" data-active={status === k} onClick={() => setStatus(k)}>{label}</button>
              ))}
            </>
          )}
        </div>
        <div style={{ position: 'relative', marginBottom: 16 }}>
          <span style={{ position: 'absolute', left: 14, top: 18, color: 'var(--ink-4)' }}><Icon d={icons.search} size={18} /></span>
          <input
            className="input-field"
            style={{ paddingLeft: 42, height: 52, background: 'var(--paper)' }}
            placeholder="Поиск по названию"
            value={query}
            onChange={(e) => setQuery(e.target.value)}
          />
        </div>

        {loading && <CenterSpinner />}
        {error && <ErrorBox message={apiErrorMessage(error)} onRetry={() => { void events.refetch(); void invited.refetch(); void collections.refetch() }} />}

        {!loading && !error && cards.length === 0 && (
          <div className="host-card" style={{ padding: '36px 24px', textAlign: 'center' }}>
            <h2 className="host-h2" style={{ marginBottom: 8 }}>{emptyTitle}</h2>
            <p className="host-muted" style={{ marginBottom: 20 }}>{emptyText}</p>
            {scope !== 'invited' && !query && (
              <Link to={newTo} className="btn" style={{ maxWidth: 280, margin: '0 auto' }}>
                <Icon d={icons.plus} /> {scope === 'solo' ? 'Новое соло' : scope === 'minis' ? 'Новая подборка' : 'Новый альбом'}
              </Link>
            )}
          </div>
        )}

        <div className="host-grid">
          {cards.map((c) => <EventCard key={`${c.kind}-${c.kind === 'mini' ? c.col.id : c.event.id}`} card={c} />)}
        </div>
      </main>
    </>
  )
}
