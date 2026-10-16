import { useRef, useState, type ReactNode } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, goToLogin, hostApi, type Schemas } from '../api/hostClient'
import { uploadPutBlob } from '../../api/client'
import { Row } from '../components/Row'
import { formatDate, rubles } from '../format'
import { qk, useMe } from '../queries'
import { CenterSpinner, copyText, ErrorBox, Icon, icons, Sheet, shareLink, Spinner, toast, TopBar } from '../ui'

async function resizeToSquareJpeg(file: File): Promise<Blob> {
  const bitmap = await createImageBitmap(file, { imageOrientation: 'from-image' })
  const size = Math.min(bitmap.width, bitmap.height)
  const canvas = document.createElement('canvas')
  canvas.width = 512
  canvas.height = 512
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new Error('Canvas 2D unavailable')
  ctx.imageSmoothingQuality = 'high'
  ctx.drawImage(bitmap, Math.floor((bitmap.width - size) / 2), Math.floor((bitmap.height - size) / 2), size, size, 0, 0, 512, 512)
  return await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((b) => (b ? resolve(b) : reject(new Error('toBlob failed'))), 'image/jpeg', 0.92)
  })
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section>
      <div className="host-field-label" style={{ margin: '4px 2px 8px' }}>{title}</div>
      <div className="host-card">{children}</div>
    </section>
  )
}

function discountLabel(p: Schemas['PromocodeOut']): string {
  return p.discount_type === 'percent' ? `−${p.discount_value}%` : `−${rubles(p.discount_value)}`
}

export default function ProfileScreen() {
  const qc = useQueryClient()
  const me = useMe()
  const fileRef = useRef<HTMLInputElement>(null)
  const [uploading, setUploading] = useState(false)
  const [nameSheet, setNameSheet] = useState(false)
  const [name, setName] = useState('')
  const [deleteSheet, setDeleteSheet] = useState(false)
  const [confirmText, setConfirmText] = useState('')

  const referrals = useQuery({
    queryKey: ['referrals'],
    queryFn: async () => (await hostApi.get<Schemas['ReferralStatsOut']>('/me/referrals')).data,
  })
  const promos = useQuery({
    queryKey: ['my-promocodes'],
    queryFn: async () => {
      const { data } = await hostApi.get<Schemas['PromocodeOut'][]>('/me/promocodes')
      return Array.isArray(data) ? data : []
    },
  })

  const saveName = useMutation({
    mutationFn: async () => { await hostApi.patch('/users/me', { display_name: name.trim() }) },
    onSuccess: () => { void qc.invalidateQueries({ queryKey: qk.me }); setNameSheet(false); toast('Имя сохранено') },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const deleteAccount = useMutation({
    mutationFn: async () => { await hostApi.delete('/users/me') },
    onSuccess: () => goToLogin(),
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const onAvatar = async (file: File | undefined) => {
    if (!file) return
    setUploading(true)
    try {
      const blob = await resizeToSquareJpeg(file)
      const { data: presign } = await hostApi.post<Schemas['AvatarPresignOut']>('/users/me/avatar/presign', {
        content_type: 'image/jpeg', size_bytes: blob.size,
      })
      await uploadPutBlob(presign.upload_url, blob, new AbortController().signal)
      await hostApi.patch('/users/me', { avatar_key: presign.avatar_key })
      await qc.invalidateQueries({ queryKey: qk.me })
      toast('Фото обновлено')
    } catch (e) {
      toast(apiErrorMessage(e, 'Не удалось загрузить фото'))
    } finally {
      setUploading(false)
      if (fileRef.current) fileRef.current.value = ''
    }
  }

  if (me.isLoading) return (<><TopBar title="Профиль" /><CenterSpinner /></>)
  if (me.error || !me.data) return (<><TopBar title="Профиль" /><main className="host-main"><ErrorBox message={apiErrorMessage(me.error)} onRetry={() => void me.refetch()} /></main></>)

  const u = me.data
  const refCode = referrals.data?.referral_code ?? u.referral_code
  const refUrl = refCode ? `https://impomento.pro/?ref=${refCode}` : null

  return (
    <>
      <TopBar title="Профиль" kicker={u.is_admin ? 'Администратор' : undefined} />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 18 }}>
        <div className="host-card" style={{ padding: 16, display: 'flex', alignItems: 'center', gap: 16 }}>
          <button onClick={() => fileRef.current?.click()} aria-label="Сменить фото" disabled={uploading}
            style={{
              width: 76, height: 76, flexShrink: 0, border: '1px solid var(--ink)', borderRadius: 2, padding: 0, cursor: 'pointer',
              background: 'repeating-linear-gradient(135deg, #1A1714 0 9px, #231E19 9px 18px)', position: 'relative', overflow: 'hidden',
              display: 'flex', alignItems: 'center', justifyContent: 'center', color: 'var(--amber)',
            }}>
            {u.avatar_url ? <img src={u.avatar_url} alt="" style={{ width: '100%', height: '100%', objectFit: 'cover' }} /> : <Icon d={icons.profile} size={30} />}
            {uploading && <span style={{ position: 'absolute', inset: 0, background: 'rgba(26,23,20,.6)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}><Spinner /></span>}
          </button>
          <input ref={fileRef} type="file" accept="image/*" hidden onChange={(ev) => void onAvatar(ev.target.files?.[0])} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="host-frame-title" style={{ margin: 0 }}>{u.display_name || 'Без имени'}</div>
            <div className="host-muted" style={{ fontSize: 13, overflow: 'hidden', textOverflow: 'ellipsis' }}>{u.email}</div>
            <button className="host-chip" style={{ marginTop: 8 }} onClick={() => { setName(u.display_name ?? ''); setNameSheet(true) }}>Изменить имя</button>
          </div>
        </div>

        <Section title="Пригласите друзей">
          {refCode ? (
            <div style={{ padding: 16 }}>
              <div className="host-edge">Ваш код</div>
              <div className="host-mono" style={{ fontSize: 26, margin: '2px 0 10px' }}>{refCode}</div>
              <p className="host-muted" style={{ marginBottom: 12 }}>
                Когда друг создаст первый платный альбом по вашей ссылке, вы оба получите скидку по промокоду.
              </p>
              <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
                <button className="host-chip" onClick={() => void copyText(refUrl!, 'Ссылка скопирована')}><Icon d={icons.copy} size={14} /> Копировать ссылку</button>
                <button className="host-chip" onClick={() => void shareLink(refUrl!, 'ImpoMento')}><Icon d={icons.share} size={14} /> Отправить</button>
              </div>
              {referrals.data && (
                <div style={{ display: 'flex', marginTop: 14, borderTop: '1px dashed var(--ink-4)' }}>
                  {([[referrals.data.referrals_count, 'друзей'], [referrals.data.pending_promocodes_count, 'промокодов'], [rubles(referrals.data.total_earned_kopecks), 'выгода']] as const).map(([v, l]) => (
                    <div key={l} style={{ flex: 1, textAlign: 'center', padding: '10px 4px' }}>
                      <div className="host-mono" style={{ fontSize: 20 }}>{v}</div>
                      <div className="host-edge" style={{ fontSize: 11 }}>{l}</div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          ) : <div className="host-muted" style={{ padding: 16 }}>Реферальный код появится после первого входа.</div>}
        </Section>

        <Section title="Мои промокоды">
          {promos.isLoading ? <div style={{ padding: 16 }}><Spinner /></div>
            : promos.data && promos.data.length > 0 ? promos.data.map((p) => (
              <button key={p.id} className="host-row" onClick={() => void copyText(p.code, 'Промокод скопирован')}>
                <span className="host-mono" style={{ fontSize: 17, flex: 1 }}>{p.code}</span>
                <span style={{ textAlign: 'right' }}>
                  <b>{discountLabel(p)}</b>
                  <span className="host-muted" style={{ display: 'block', fontSize: 12 }}>
                    {p.expires_at ? `до ${formatDate(p.expires_at)}` : 'без срока'}
                  </span>
                </span>
              </button>
            ))
            : <div className="host-muted" style={{ padding: 16 }}>Пока нет промокодов. Их выдают за приглашённых друзей.</div>}
        </Section>

        <Section title="Прочее">
          <Row icon={icons.albums} label="Как это работает" hint="Вопросы и ответы" onClick={() => window.open('/about.html', '_blank', 'noopener')} />
          <Row icon={icons.lock} label="Оферта и политика" onClick={() => window.open('/offer.html', '_blank', 'noopener')} />
          <Row icon={icons.logout} label="Выйти" onClick={() => goToLogin()} />
          <Row icon={icons.trash} label="Удалить аккаунт" danger onClick={() => { setConfirmText(''); setDeleteSheet(true) }} />
        </Section>
      </main>

      <Sheet open={nameSheet} onClose={() => setNameSheet(false)} title="Ваше имя">
        <input className="input-field" maxLength={120} value={name} onChange={(e) => setName(e.target.value)} autoFocus />
        <button className="btn" style={{ marginTop: 16 }} disabled={saveName.isPending || name.trim().length < 1} onClick={() => saveName.mutate()}>
          {saveName.isPending ? <Spinner /> : 'Сохранить'}
        </button>
      </Sheet>

      <Sheet open={deleteSheet} onClose={() => setDeleteSheet(false)} title="Удалить аккаунт?">
        <p className="host-muted" style={{ marginBottom: 14 }}>
          Все ваши события, кадры и архивы будут удалены без возможности восстановления. Чтобы подтвердить, введите слово <b>УДАЛИТЬ</b>.
        </p>
        <input className="input-field" value={confirmText} onChange={(e) => setConfirmText(e.target.value)} placeholder="УДАЛИТЬ" />
        <button className="btn-danger" style={{ marginTop: 14 }} disabled={confirmText.trim().toUpperCase() !== 'УДАЛИТЬ' || deleteAccount.isPending} onClick={() => deleteAccount.mutate()}>
          {deleteAccount.isPending ? <Spinner /> : 'Удалить навсегда'}
        </button>
        <button className="btn-ghost" style={{ marginTop: 10 }} onClick={() => setDeleteSheet(false)}>Отмена</button>
      </Sheet>
    </>
  )
}
