import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type EventOut } from '../api/hostClient'
import { FILM_LABELS } from '../format'
import { qk, useEntitlements } from '../queries'
import { Spinner, toast, TopBar } from '../ui'

const FILMS = ['portra400', 'fuji400h', 'cinestill', 'ilford', 'original'] as const

export default function CreateSoloScreen() {
  const navigate = useNavigate()
  const qc = useQueryClient()
  const ent = useEntitlements().data
  const [title, setTitle] = useState('')
  const [film, setFilm] = useState<(typeof FILMS)[number]>('portra400')

  const create = useMutation({
    mutationFn: async () => (await hostApi.post<EventOut>('/events/solo', { title: title.trim(), lut_preset: film })).data,
    onSuccess: (ev) => {
      void qc.invalidateQueries({ queryKey: qk.events })
      void qc.invalidateQueries({ queryKey: qk.entitlements })
      navigate(`/app/events/${ev.id}`, { replace: true })
    },
    onError: (e) => toast(apiErrorMessage(e)),
  })

  const blocked = ent ? ent.solo_frames_left <= 0 : false

  return (
    <>
      <TopBar back="/app/new" title="Соло-альбом" kicker="Новый альбом" />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 18 }}>
        <div>
          <label className="host-field-label" htmlFor="solo-title">Название</label>
          <input id="solo-title" className="input-display" maxLength={80} placeholder="Например, Грузия, осень"
            value={title} onChange={(e) => setTitle(e.target.value)} autoFocus />
        </div>

        <div>
          <div className="host-field-label">Плёнка</div>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
            {FILMS.map((f) => (
              <button key={f} className="host-chip" data-active={film === f} onClick={() => setFilm(f)}>{FILM_LABELS[f].name}</button>
            ))}
          </div>
        </div>

        {ent && (
          <div className="host-card" style={{ padding: 14 }}>
            <div className="host-edge">Ваши лимиты</div>
            <p style={{ margin: '6px 0 0', lineHeight: 1.5 }}>
              В этом месяце можно снять ещё <b>{ent.solo_frames_left}</b> из {ent.solo_frames_per_month} кадров во всех соло-альбомах.
              Альбом хранится {ent.solo_retention_days} дн., потом его можно продлить.
            </p>
          </div>
        )}

        <button className="btn" disabled={create.isPending || title.trim().length < 1 || blocked} onClick={() => create.mutate()}>
          {create.isPending ? <Spinner /> : 'Создать альбом'}
        </button>
        {blocked && <p className="host-muted">Лимит кадров на этот месяц исчерпан. Новые откроются с 1-го числа.</p>}
      </main>
    </>
  )
}
