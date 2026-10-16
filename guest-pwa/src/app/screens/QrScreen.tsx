import { useEffect, useRef, useState } from 'react'
import { useParams } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import QRCode from 'qrcode'
import { apiErrorMessage, hostApi } from '../api/hostClient'
import { guestLink } from '../format'
import { qk, useEvent } from '../queries'
import { copyText, ErrorBox, Icon, icons, CenterSpinner, shareLink, toast, TopBar } from '../ui'
import { QR_PRESETS, parseQrPreset, type QrPreset } from '../styles'

const SIZE = 720

async function renderQr(canvas: HTMLCanvasElement, url: string, preset: QrPreset) {
  const p = QR_PRESETS[preset]
  await QRCode.toCanvas(canvas, url, {
    width: SIZE, margin: 2, errorCorrectionLevel: 'M',
    color: { dark: p.modules, light: p.canvas },
  })
  // Библиотека прописывает фиксированный размер в пикселях — возвращаем адаптивный.
  canvas.style.width = '100%'
  canvas.style.height = 'auto'
}

export default function QrScreen() {
  const { id = '' } = useParams()
  const qc = useQueryClient()
  const event = useEvent(id)
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const [local, setLocal] = useState<QrPreset | null>(null)
  const preset = local ?? parseQrPreset(event.data?.settings.qr_style)
  const url = event.data ? guestLink(event.data.short_code) : ''
  const style = QR_PRESETS[preset]

  useEffect(() => {
    if (!canvasRef.current || !url) return
    void renderQr(canvasRef.current, url, preset)
  }, [url, preset])

  const save = useMutation({
    mutationFn: async (p: QrPreset) => (await hostApi.patch(`/events/${id}/settings`, { qr_style: p })).data,
    onSuccess: () => { void qc.invalidateQueries({ queryKey: qk.event(id) }) },
    onError: (e) => { setLocal(null); toast(apiErrorMessage(e, 'Не удалось сохранить стиль')) },
  })
  const choose = (p: QrPreset) => { setLocal(p); save.mutate(p) }

  const download = () => {
    const canvas = canvasRef.current
    if (!canvas) return
    const a = document.createElement('a')
    a.href = canvas.toDataURL('image/png')
    a.download = `qr-${event.data?.short_code ?? 'album'}.png`
    a.click()
  }

  if (event.isLoading) return (<><TopBar back={`/app/events/${id}`} title="QR-код" /><CenterSpinner /></>)
  if (event.error || !event.data) {
    return (<><TopBar back="/app" title="QR-код" /><main className="host-main"><ErrorBox message={apiErrorMessage(event.error, 'Событие не найдено')} /></main></>)
  }

  return (
    <>
      <TopBar back={`/app/events/${id}`} title="QR для гостей" />
      <main className="host-main" style={{ paddingTop: 16, display: 'flex', flexDirection: 'column', gap: 16, alignItems: 'center' }}>
        <div style={{
          background: style.canvas, border: '1px solid var(--ink)', borderRadius: 2, padding: 20, width: '100%', maxWidth: 380,
          boxShadow: '5px 5px 0 var(--ink)',
          color: style.modules, textAlign: 'center',
        }}>
          <canvas ref={canvasRef} width={SIZE} height={SIZE} style={{ width: '100%', height: 'auto', display: 'block' }} aria-label={`QR-код альбома ${event.data.title}`} />
          <div style={{ fontFamily: 'Playfair Display, serif', fontWeight: 600, fontSize: 20, marginTop: 14 }}>{event.data.title}</div>
        </div>

        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 14, color: 'var(--ink-2)', wordBreak: 'break-all', textAlign: 'center' }}>{url}</div>
        <p className="host-muted" style={{ textAlign: 'center', maxWidth: 360 }}>
          Покажите QR на экране или распечатайте. Гость наводит камеру телефона, открывается камера в браузере, ничего ставить не нужно.
        </p>

        <div style={{ display: 'flex', gap: 8, width: '100%', maxWidth: 380 }}>
          <button className="btn-ghost btn-sm" onClick={() => void copyText(url, 'Ссылка скопирована')}><Icon d={icons.copy} size={16} /> Ссылка</button>
          <button className="btn-ghost btn-sm" onClick={() => void shareLink(url, event.data!.title)}><Icon d={icons.share} size={16} /> Поделиться</button>
          <button className="btn-ghost btn-sm" onClick={download}><Icon d={icons.download} size={16} /> PNG</button>
        </div>

        <div style={{ width: '100%', maxWidth: 380 }}>
          <div className="host-field-label">Стиль QR-кода</div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
            {(Object.keys(QR_PRESETS) as QrPreset[]).map((p) => (
              <button key={p} onClick={() => choose(p)} aria-pressed={preset === p}
                style={{
                  background: QR_PRESETS[p].canvas, color: QR_PRESETS[p].modules, borderRadius: 2, height: 64, cursor: 'pointer',
                  border: preset === p ? '2px solid var(--amber)' : '2px solid var(--line)', fontSize: 12, fontWeight: 600,
                }}>{QR_PRESETS[p].label}</button>
            ))}
          </div>
        </div>
      </main>
    </>
  )
}
