import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { copyText, Icon, icons, Sheet, shareLink, Spinner, toast } from '../ui'

/** Открытая ссылка на альбом, соло-альбом или подборку: включить, скопировать, отправить, обновить, отключить. */
export function PublicLinkSheet({ base, title, open, onClose, note }: {
  /** Путь API без префикса: `/events/<id>` или `/collections/<id>`. */
  base: string
  title: string
  open: boolean
  onClose: () => void
  note?: string
}) {
  const qc = useQueryClient()
  const key = ['public-share', base]
  const q = useQuery({
    queryKey: key,
    enabled: open,
    queryFn: async () => (await hostApi.get<Schemas['PublicShareOut']>(`${base}/public-share`)).data,
  })
  const act = useMutation({
    mutationFn: async (action: 'enable' | 'regenerate' | 'delete') => {
      if (action === 'delete') await hostApi.delete(`${base}/public-share`)
      else await hostApi.post(`${base}/public-share/${action}`)
      return action
    },
    onSuccess: (action) => {
      void qc.invalidateQueries({ queryKey: key })
      toast(action === 'delete' ? 'Открытая ссылка отключена' : action === 'enable' ? 'Открытая ссылка включена' : 'Ссылка обновлена')
    },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const token = q.data?.public_share_token
  const url = token ? `${window.location.origin}/a/${token}` : null

  return (
    <Sheet open={open} onClose={onClose} title="Поделиться ссылкой">
      {q.isLoading ? <div style={{ padding: 20, textAlign: 'center' }}><Spinner /></div> : q.error ? (
        <p className="host-muted">{apiErrorMessage(q.error)}</p>
      ) : url ? (
        <>
          <div className="host-mono" style={{ wordBreak: 'break-all', marginBottom: 10 }}>{url}</div>
          <p className="host-muted" style={{ marginBottom: 14 }}>
            {note ?? 'Любой, у кого есть ссылка, увидит кадры. Вы отвечаете за её распространение.'}
          </p>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <button className="btn btn-sm" style={{ flex: '1 1 160px' }} onClick={() => void shareLink(url, title)}><Icon d={icons.share} size={18} /> Отправить</button>
            <button className="btn-ghost btn-sm" style={{ flex: '1 1 160px' }} onClick={() => void copyText(url, 'Ссылка скопирована')}><Icon d={icons.copy} size={18} /> Копировать</button>
          </div>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', marginTop: 10 }}>
            <button className="host-chip" disabled={act.isPending} onClick={() => act.mutate('regenerate')}>Обновить ссылку</button>
            <button className="host-chip" style={{ color: 'var(--shutter)' }} disabled={act.isPending} onClick={() => act.mutate('delete')}>Отключить</button>
          </div>
        </>
      ) : (
        <>
          <p className="host-muted" style={{ marginBottom: 14 }}>
            Ссылка выключена. Включив её, вы разрешаете просмотр всем, у кого она будет, и берёте на себя ответственность за её распространение.
          </p>
          <button className="btn" disabled={act.isPending} onClick={() => act.mutate('enable')}>{act.isPending ? <Spinner /> : 'Включить ссылку'}</button>
        </>
      )}
    </Sheet>
  )
}
