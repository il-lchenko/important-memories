import { useState } from 'react'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import { apiErrorMessage, hostApi, type EventOut } from '../api/hostClient'
import { EVENT_TYPE_LABELS, FILM_LABELS, formatDateTime } from '../format'
import { qk } from '../queries'
import { icons, Sheet, Spinner, toast } from '../ui'
import { FilmPicker } from './FilmPicker'
import { FramesSlider } from './FramesSlider'
import { DateTimeField } from './pickers'
import { Row } from './Row'

/** ISO → значение для datetime-local в часовом поясе устройства. */
export function toLocalInput(iso?: string | null): string {
  if (!iso) return ''
  const d = new Date(iso)
  const p = (n: number) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}`
}

type Which = 'title' | 'type' | 'start' | 'reveal' | 'film' | 'frames' | null

/** Редактирование события: название, тип, начало, время проявки, плёнка и число кадров. */
export function EventEdit({ e }: { e: EventOut }) {
  const qc = useQueryClient()
  const [which, setWhich] = useState<Which>(null)
  const [title, setTitle] = useState(e.title)
  const [type, setType] = useState(e.event_type)
  const [start, setStart] = useState(toLocalInput(e.start_at))
  const [timer, setTimer] = useState(e.settings.reveal_mode === 'delayed')
  const [reveal, setReveal] = useState(toLocalInput(e.settings.reveal_at))
  const [film, setFilm] = useState(e.settings.lut_preset)
  const [frames, setFrames] = useState(e.settings.frames_per_guest)

  const locked = e.settings_locked === true
  const s = e.settings

  const done = () => {
    void qc.invalidateQueries({ queryKey: qk.event(e.id) })
    void qc.invalidateQueries({ queryKey: qk.events })
    setWhich(null)
    toast('Сохранено')
  }
  const patchEvent = useMutation({
    mutationFn: async (body: Record<string, unknown>) => { await hostApi.patch(`/events/${e.id}`, body) },
    onSuccess: done,
    onError: (err) => toast(apiErrorMessage(err)),
  })
  const patchSettings = useMutation({
    mutationFn: async (body: Record<string, unknown>) => { await hostApi.patch(`/events/${e.id}/settings`, body) },
    onSuccess: done,
    onError: (err) => toast(apiErrorMessage(err)),
  })
  const busy = patchEvent.isPending || patchSettings.isPending

  const open = (w: Which) => {
    setTitle(e.title); setType(e.event_type); setStart(toLocalInput(e.start_at))
    setTimer(s.reveal_mode === 'delayed'); setReveal(toLocalInput(s.reveal_at))
    setFilm(s.lut_preset); setFrames(s.frames_per_guest)
    setWhich(w)
  }

  const saveReveal = () => {
    if (!timer) { patchEvent.mutate({ reveal_mode: 'instant' }); return }
    if (!reveal) { toast('Укажите дату и время проявки'); return }
    const at = new Date(reveal)
    if (at.getTime() <= Date.now()) { toast('Время проявки должно быть в будущем'); return }
    patchEvent.mutate({ reveal_mode: 'delayed', reveal_at: at.toISOString() })
  }

  return (
    <>
      <Row icon={icons.settings} label="Название" hint={e.title} onClick={() => open('title')} />
      <Row icon={icons.albums} label="Тип события" hint={EVENT_TYPE_LABELS[e.event_type] ?? 'Другое'} onClick={() => open('type')} />
      <Row icon={icons.camera} label="Начало съёмки" hint={formatDateTime(e.start_at)} onClick={() => open('start')} />
      <Row icon={icons.lock} label="Проявка альбома"
        hint={s.reveal_mode === 'delayed' && s.reveal_at ? `Откроется ${formatDateTime(s.reveal_at)}` : 'Откроете сами, когда решите'}
        onClick={() => open('reveal')} />
      <Row icon={icons.frames} label="Плёнка" hint={locked ? `${FILM_LABELS[s.lut_preset]?.name ?? '—'} · после первого гостя не меняется` : FILM_LABELS[s.lut_preset]?.name ?? '—'}
        onClick={() => (locked ? toast('Плёнку нельзя менять после того, как вошёл первый гость') : open('film'))} />
      <Row icon={icons.users} label="Кадров на гостя"
        hint={locked ? `${s.frames_per_guest} · после первого гостя не меняется` : String(s.frames_per_guest)}
        onClick={() => (locked ? toast('Число кадров нельзя менять после того, как вошёл первый гость') : s.frames_per_guest > 30 ? toast('Больше 30 кадров куплено отдельно, изменить можно в доплатах') : open('frames'))} />

      <Sheet open={which === 'title'} onClose={() => setWhich(null)} title="Название события">
        <input className="input-field" maxLength={80} value={title} onChange={(ev) => setTitle(ev.target.value)} autoFocus />
        <button className="btn" style={{ marginTop: 16 }} disabled={busy || title.trim().length < 1} onClick={() => patchEvent.mutate({ title: title.trim() })}>
          {busy ? <Spinner /> : 'Сохранить'}
        </button>
      </Sheet>

      <Sheet open={which === 'type'} onClose={() => setWhich(null)} title="Тип события">
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 8 }}>
          {Object.entries(EVENT_TYPE_LABELS).map(([k, label]) => (
            <button key={k} onClick={() => setType(k as typeof type)}
              style={{
                padding: '14px 6px', borderRadius: 14, cursor: 'pointer', fontFamily: 'Manrope, sans-serif', fontSize: 13, fontWeight: 600,
                border: type === k ? '1.5px solid var(--amber)' : '1.5px solid transparent',
                background: type === k ? 'rgba(201,136,30,.08)' : 'var(--paper-2)', color: 'var(--ink)',
              }}>{label}</button>
          ))}
        </div>
        <button className="btn" style={{ marginTop: 16 }} disabled={busy} onClick={() => patchEvent.mutate({ event_type: type })}>{busy ? <Spinner /> : 'Сохранить'}</button>
      </Sheet>

      <Sheet open={which === 'start'} onClose={() => setWhich(null)} title="Начало съёмки">
        <p className="host-muted" style={{ marginBottom: 12 }}>Гости смогут снимать, начиная с этого времени.</p>
        <DateTimeField value={start} onChange={setStart} max={new Date(Date.now() + 730 * 86400000)} placeholder="Выберите дату и время" />
        <button className="btn" style={{ marginTop: 16 }} disabled={busy || !start} onClick={() => patchEvent.mutate({ start_at: new Date(start).toISOString() })}>{busy ? <Spinner /> : 'Сохранить'}</button>
      </Sheet>

      <Sheet open={which === 'reveal'} onClose={() => setWhich(null)} title="Проявка альбома">
        <div className="host-scroll-x" style={{ marginBottom: 14 }}>
          <button className="host-chip" data-active={!timer} onClick={() => setTimer(false)}>Открою сам</button>
          <button className="host-chip" data-active={timer} onClick={() => setTimer(true)}>По таймеру</button>
        </div>
        {timer ? (
          <>
            <p className="host-muted" style={{ marginBottom: 12 }}>В это время съёмка закончится, а альбом откроется гостям.</p>
            <DateTimeField value={reveal} onChange={setReveal} min={new Date()} max={new Date(Date.now() + 730 * 86400000)} placeholder="Выберите дату и время" />
          </>
        ) : (
          <p className="host-muted">Альбом откроется, когда вы нажмёте «Открыть альбом сейчас».</p>
        )}
        <button className="btn" style={{ marginTop: 16 }} disabled={busy} onClick={saveReveal}>{busy ? <Spinner /> : 'Сохранить'}</button>
      </Sheet>

      <Sheet open={which === 'film'} onClose={() => setWhich(null)} title="Плёнка">
        <FilmPicker value={film} onChange={setFilm} />
        <button className="btn" style={{ marginTop: 16 }} disabled={busy} onClick={() => patchSettings.mutate({ lut_preset: film })}>{busy ? <Spinner /> : 'Сохранить'}</button>
      </Sheet>

      <Sheet open={which === 'frames'} onClose={() => setWhich(null)} title="Кадров на гостя">
        <FramesSlider value={Math.min(Math.max(frames, 6), 30)} onChange={setFrames} />
        <div style={{ height: 12 }} />
        <p className="host-muted">До 30 кадров входит в тариф. Больше можно докупить в разделе «Тариф».</p>
        <button className="btn" style={{ marginTop: 16 }} disabled={busy} onClick={() => patchSettings.mutate({ frames_per_guest: frames })}>{busy ? <Spinner /> : 'Сохранить'}</button>
      </Sheet>
    </>
  )
}
