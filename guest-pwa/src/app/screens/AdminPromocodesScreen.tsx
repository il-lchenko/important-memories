import { useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { formatDate, rubles } from '../format'
import { CenterSpinner, ErrorBox, Icon, icons, Sheet, Spinner, toast, TopBar } from '../ui'

type Promo = Schemas['PromocodeOut']

const APPLIES: Array<[Promo['applies_to'], string]> = [
  ['all', 'Везде'], ['checkout', 'Запуск события'], ['extend', 'Продление'], ['upgrade', 'Доплаты'],
]

function discountText(p: Promo) {
  return p.discount_type === 'percent' ? `−${p.discount_value}%` : `−${rubles(p.discount_value)}`
}

/** Промокоды: список, создание и удаление. Только для администраторов. */
export default function AdminPromocodesScreen() {
  const qc = useQueryClient()
  const list = useQuery({
    queryKey: ['admin-promocodes'],
    queryFn: async () => (await hostApi.get<Promo[]>('/admin/promocodes')).data,
  })
  const [sheet, setSheet] = useState(false)
  const [code, setCode] = useState('')
  const [type, setType] = useState<'percent' | 'fixed'>('percent')
  const [value, setValue] = useState('10')
  const [max, setMax] = useState('')
  const [until, setUntil] = useState('')
  const [applies, setApplies] = useState<Promo['applies_to']>('all')
  const [owner, setOwner] = useState('')

  const create = useMutation({
    mutationFn: async () => {
      const v = Number(value)
      await hostApi.post('/admin/promocodes', {
        code: code.trim().toUpperCase(),
        kind: 'manual',
        discount_type: type,
        discount_value: type === 'fixed' ? Math.round(v * 100) : Math.round(v),
        max_redemptions: max ? Number(max) : null,
        expires_at: until ? new Date(`${until}T23:59:59`).toISOString() : null,
        applies_to: applies,
        owner_user_email: owner.trim() || null,
      })
    },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['admin-promocodes'] }); setSheet(false); setCode(''); toast('Промокод создан') },
    onError: (e) => toast(apiErrorMessage(e)),
  })
  const remove = useMutation({
    mutationFn: async (id: string) => { await hostApi.delete(`/admin/promocodes/${id}`) },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: ['admin-promocodes'] }); toast('Удалён') },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const valid = code.trim().length >= 3 && Number(value) > 0 && (type !== 'percent' || Number(value) <= 100)

  return (
    <>
      <TopBar back="/app/profile" title="Промокоды" kicker="Администратор"
        right={<button className="host-icon-btn" aria-label="Новый промокод" onClick={() => setSheet(true)}><Icon d={icons.plus} /></button>} />
      <main className="host-main" style={{ paddingTop: 12, display: 'flex', flexDirection: 'column', gap: 10 }}>
        {list.isLoading && <CenterSpinner />}
        {list.error && <ErrorBox message={apiErrorMessage(list.error)} onRetry={() => void list.refetch()} />}
        {list.data?.length === 0 && <div className="host-card" style={{ padding: 24, textAlign: 'center' }}><p className="host-muted">Промокодов пока нет.</p></div>}
        {list.data?.map((p) => (
          <div key={p.id} className="host-card" style={{ padding: 16 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <span className="host-mono" style={{ fontSize: 18, flex: 1 }}>{p.code}</span>
              <b>{discountText(p)}</b>
            </div>
            <div className="host-muted" style={{ fontSize: 13, marginTop: 6 }}>
              {APPLIES.find(([k]) => k === p.applies_to)?.[1]} · использовано {p.redemptions_count}{p.max_redemptions ? ` из ${p.max_redemptions}` : ''}
              {p.expires_at ? ` · до ${formatDate(p.expires_at)}` : ' · без срока'}
              {p.kind !== 'manual' ? ` · ${p.kind === 'referral' ? 'реферальный' : p.kind}` : ''}
            </div>
            <div style={{ marginTop: 10 }}>
              <button className="host-chip" style={{ color: 'var(--shutter)' }} disabled={remove.isPending} onClick={() => remove.mutate(p.id)}>Удалить</button>
            </div>
          </div>
        ))}
      </main>

      <Sheet open={sheet} onClose={() => setSheet(false)} title="Новый промокод">
        <label className="host-field-label" htmlFor="pc-code">Код</label>
        <input id="pc-code" className="input-field" maxLength={32} placeholder="SUMMER25" value={code} onChange={(e) => setCode(e.target.value)} style={{ textTransform: 'uppercase' }} />
        <div className="host-scroll-x" style={{ margin: '14px 0 10px' }}>
          <button className="host-chip" data-active={type === 'percent'} onClick={() => setType('percent')}>Процент</button>
          <button className="host-chip" data-active={type === 'fixed'} onClick={() => setType('fixed')}>Рубли</button>
        </div>
        <input className="input-field" inputMode="numeric" value={value} onChange={(e) => setValue(e.target.value.replace(/\D/g, ''))} placeholder={type === 'percent' ? 'Скидка, %' : 'Скидка, ₽'} />
        <label className="host-field-label" htmlFor="pc-max" style={{ marginTop: 14 }}>Сколько раз можно применить (пусто: без лимита)</label>
        <input id="pc-max" className="input-field" inputMode="numeric" value={max} onChange={(e) => setMax(e.target.value.replace(/\D/g, ''))} />
        <label className="host-field-label" htmlFor="pc-until" style={{ marginTop: 14 }}>Действует до (пусто: без срока)</label>
        <input id="pc-until" className="input-field" type="date" value={until} onChange={(e) => setUntil(e.target.value)} />
        <div className="host-field-label" style={{ marginTop: 14 }}>Где работает</div>
        <div className="host-scroll-x">
          {APPLIES.map(([k, label]) => <button key={k} className="host-chip" data-active={applies === k} onClick={() => setApplies(k)}>{label}</button>)}
        </div>
        <label className="host-field-label" htmlFor="pc-owner" style={{ marginTop: 14 }}>Только для почты (необязательно)</label>
        <input id="pc-owner" className="input-field" type="email" value={owner} onChange={(e) => setOwner(e.target.value)} />
        <button className="btn" style={{ marginTop: 18 }} disabled={!valid || create.isPending} onClick={() => create.mutate()}>
          {create.isPending ? <Spinner /> : 'Создать'}
        </button>
      </Sheet>
    </>
  )
}
