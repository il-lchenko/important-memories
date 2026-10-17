import { useState } from 'react'
import { useParams } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { formatDateTime } from '../format'
import { useEvent } from '../queries'
import { CenterSpinner, copyText, ErrorBox, Icon, icons, Sheet, shareLink, Spinner, toast, TopBar } from '../ui'

type Invite = Schemas['InviteTokenOut']

export default function InvitesScreen() {
  const { id = '' } = useParams()
  const qc = useQueryClient()
  const event = useEvent(id)
  const [sheet, setSheet] = useState(false)
  const [name, setName] = useState('')
  const [days, setDays] = useState(14)

  const invites = useQuery({
    queryKey: ['invites', id],
    queryFn: async () => {
      const { data } = await hostApi.get<Invite[] | Invite>(`/events/${id}/invites`)
      return Array.isArray(data) ? data : []
    },
  })

  const create = useMutation({
    mutationFn: async () => (await hostApi.post<Invite>(`/events/${id}/invites`, { display_name: name.trim(), ttl_days: days })).data,
    onSuccess: (inv) => {
      void qc.invalidateQueries({ queryKey: ['invites', id] })
      setSheet(false); setName('')
      if (inv.invite_url) void copyText(inv.invite_url, 'Ссылка скопирована')
    },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const remove = useMutation({
    mutationFn: async (inviteId: string) => { await hostApi.delete(`/events/${id}/invites/${inviteId}`) },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['invites', id] }); toast('Приглашение удалено') },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const canInvite = event.data?.status === 'active'
  const title = event.data?.title ?? 'Событие'

  return (
    <>
      <TopBar back={`/app/events/${id}`} title="Личные приглашения" kicker={title}
        right={canInvite ? <button className="host-icon-btn" aria-label="Новое приглашение" onClick={() => setSheet(true)}><Icon d={icons.plus} /></button> : undefined} />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 12 }}>
        <p className="host-muted">
          Личная ссылка открывает альбом конкретному гостю под его именем, без кода и PIN. Подходит для близких, которых вы ждёте.
          {!canInvite && ' Создавать приглашения можно, пока событие идёт.'}
        </p>

        {invites.isLoading && <CenterSpinner />}
        {invites.error && <ErrorBox message={apiErrorMessage(invites.error)} onRetry={() => void invites.refetch()} />}

        {invites.data?.length === 0 && (
          <div className="host-card" style={{ padding: 24, textAlign: 'center' }}>
            <h2 className="host-h2" style={{ marginBottom: 6 }}>Пока никого не приглашали</h2>
            {canInvite && <button className="btn" style={{ maxWidth: 260, margin: '14px auto 0' }} onClick={() => setSheet(true)}><Icon d={icons.plus} /> Пригласить гостя</button>}
          </div>
        )}

        {invites.data?.map((inv) => (
          <div key={inv.id} className="host-card" style={{ padding: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div className="host-frame-title" style={{ margin: 0, fontSize: 18 }}>{inv.display_name}</div>
                <div className="host-edge" style={{ marginTop: 4 }}>
                  {inv.used_at ? `вошёл ${formatDateTime(inv.used_at)}` : inv.expires_at ? `до ${formatDateTime(inv.expires_at)}` : 'без срока'}
                </div>
              </div>
              {inv.used_at && <span className="host-badge" style={{ color: 'var(--success)' }}>Вошёл</span>}
            </div>
            {inv.invite_url && (
              <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
                <button className="host-chip" onClick={() => void copyText(inv.invite_url!, 'Ссылка скопирована')}><Icon d={icons.copy} size={14} /> Копировать</button>
                <button className="host-chip" onClick={() => void shareLink(inv.invite_url!, `${title}: приглашение`)}><Icon d={icons.share} size={14} /> Отправить</button>
                <span style={{ flex: 1 }} />
                <button className="host-chip" style={{ color: 'var(--shutter)' }} disabled={remove.isPending} onClick={() => remove.mutate(inv.id)}>Удалить</button>
              </div>
            )}
          </div>
        ))}
      </main>

      <Sheet open={sheet} onClose={() => setSheet(false)} title="Новое приглашение">
        <label className="host-field-label" htmlFor="inv-name">Как зовут гостя</label>
        <input id="inv-name" className="input-field" maxLength={60} placeholder="Например, Анна" value={name} onChange={(e) => setName(e.target.value)} autoFocus />
        <label className="host-field-label" htmlFor="inv-days" style={{ marginTop: 14 }}>Ссылка действует: {days} дн.</label>
        <input id="inv-days" className="host-range" type="range" min={1} max={90} step={1} value={days} onChange={(e) => setDays(Number(e.target.value))} style={{ ['--pct' as string]: `${((days - 1) / 89) * 100}%` }} />
        <button className="btn" style={{ marginTop: 18 }} disabled={create.isPending || name.trim().length < 1} onClick={() => create.mutate()}>
          {create.isPending ? <Spinner /> : 'Создать и скопировать ссылку'}
        </button>
      </Sheet>
    </>
  )
}
