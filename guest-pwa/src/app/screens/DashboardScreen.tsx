import { useMemo, useState } from 'react'
import { Link } from 'react-router-dom'
import type { EventOut, InvitedEventOut } from '../api/hostClient'
import { apiErrorMessage } from '../api/hostClient'
import { EVENT_TYPE_LABELS, STATUS_META, formatShortDate, pluralize } from '../format'
import { useEvents, useInvitedEvents, useMe } from '../queries'
import { CenterSpinner, ErrorBox, Icon, icons, TopBar } from '../ui'

type Scope = 'mine' | 'invited' | 'all'
type StatusFilter = 'all' | 'active' | 'completed'

type Card =
  | { kind: 'mine'; event: EventOut }
  | { kind: 'invited'; event: InvitedEventOut }

function StatusBadge({ status }: { status: string }) {
  const meta = STATUS_META[status] ?? STATUS_META.draft
  return (
    <span className="host-badge" style={{ color: meta.color, background: meta.bg }}>
      <span className="host-badge-dot" /> {meta.label}
    </span>
  )
}

function EventCard({ card }: { card: Card }) {
  const e = card.event
  const href = card.kind === 'mine' ? `/app/events/${e.id}` : `/app/events/${e.id}/album`
  const coverUrl = e.cover_url ?? null
  return (
    <Link to={href} className="host-card" style={{ display: 'block', textDecoration: 'none', color: 'inherit' }}>
      <div className="host-cover">
        {coverUrl && <img src={coverUrl} alt="" loading="lazy" />}
        <div style={{ position: 'absolute', top: 12, left: 12, display: 'flex', gap: 6 }}>
          <StatusBadge status={e.status} />
          {card.kind === 'invited' && (
            <span className="host-badge" style={{ color: 'var(--ink)', background: 'var(--paper)' }}>Гость</span>
          )}
        </div>
      </div>
      <div style={{ padding: '14px 16px 16px' }}>
        <div style={{ fontFamily: 'Playfair Display, serif', fontWeight: 600, fontSize: 20, lineHeight: 1.2, marginBottom: 6 }}>
          {e.title}
        </div>
        <div className="host-muted" style={{ fontSize: 13, display: 'flex', gap: 10, flexWrap: 'wrap' }}>
          {card.kind === 'mine' ? (
            <>
              <span>{EVENT_TYPE_LABELS[card.event.event_type] ?? 'Событие'}</span>
              <span>· {formatShortDate(card.event.start_at)}</span>
              <span>· {card.event.guests_count ?? 0} {pluralize(card.event.guests_count ?? 0, 'гость', 'гостя', 'гостей')}</span>
              <span>· {card.event.frames_count ?? 0} {pluralize(card.event.frames_count ?? 0, 'кадр', 'кадра', 'кадров')}</span>
            </>
          ) : (
            <>
              <span>{formatShortDate(card.event.start_at)}</span>
              <span>· мои кадры {card.event.my_frames_count} из {card.event.total_frames}</span>
            </>
          )}
        </div>
      </div>
    </Link>
  )
}

export default function DashboardScreen() {
  const events = useEvents()
  const invited = useInvitedEvents()
  const me = useMe()
  const [scope, setScope] = useState<Scope>('mine')
  const [status, setStatus] = useState<StatusFilter>('all')
  const [query, setQuery] = useState('')

  const cards = useMemo<Card[]>(() => {
    const mine: Card[] = (events.data ?? [])
      .filter((e) => e.status !== 'cancelled')
      .map((event) => ({ kind: 'mine', event }))
    const inv: Card[] = (invited.data ?? []).map((event) => ({ kind: 'invited', event }))
    const list = scope === 'mine' ? mine : scope === 'invited' ? inv : [...mine, ...inv]
    const q = query.trim().toLowerCase()
    return list
      .filter((c) => (status === 'all' ? true : c.event.status === status))
      .filter((c) => (q ? c.event.title.toLowerCase().includes(q) : true))
      .sort((a, b) => (b.event.start_at ?? '').localeCompare(a.event.start_at ?? ''))
  }, [events.data, invited.data, scope, status, query])

  const loading = events.isLoading || (scope !== 'mine' && invited.isLoading)
  const error = events.error ?? (scope !== 'mine' ? invited.error : null)

  return (
    <>
      <TopBar title="Альбомы" kicker={me.data?.is_admin ? 'Админ-режим · платежи в обход' : undefined} />
      <main className="host-main">
        <div style={{ display: 'flex', gap: 8, overflowX: 'auto', padding: '16px 0 10px' }}>
          {([['mine', 'Мои'], ['invited', 'Другие события'], ['all', 'Все']] as const).map(([k, label]) => (
            <button key={k} className="host-chip" data-active={scope === k} onClick={() => setScope(k)}>{label}</button>
          ))}
          <span style={{ width: 1, background: 'var(--line)', margin: '4px 2px' }} />
          {([['all', 'Любой статус'], ['active', 'Идут'], ['completed', 'Завершены']] as const).map(([k, label]) => (
            <button key={k} className="host-chip" data-active={status === k} onClick={() => setStatus(k)}>{label}</button>
          ))}
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
        {error && <ErrorBox message={apiErrorMessage(error)} onRetry={() => { void events.refetch(); void invited.refetch() }} />}

        {!loading && !error && cards.length === 0 && (
          <div className="host-card" style={{ padding: '36px 24px', textAlign: 'center' }}>
            <h2 className="host-h2" style={{ marginBottom: 8 }}>
              {query || status !== 'all' ? 'Ничего не нашлось' : scope === 'invited' ? 'Пока нет событий, где вы гость' : 'Создайте первый альбом'}
            </h2>
            <p className="host-muted" style={{ marginBottom: 20 }}>
              Гости снимают на свои телефоны по QR-коду, а все кадры собираются в одном альбоме.
            </p>
            {scope !== 'invited' && !query && (
              <Link to="/app/events/new" className="btn" style={{ maxWidth: 280, margin: '0 auto' }}>
                <Icon d={icons.plus} /> Новый альбом
              </Link>
            )}
          </div>
        )}

        <div className="host-grid">
          {cards.map((c) => <EventCard key={`${c.kind}-${c.event.id}`} card={c} />)}
        </div>
      </main>
    </>
  )
}
