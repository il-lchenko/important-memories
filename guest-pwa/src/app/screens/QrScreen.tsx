import { useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useMutation, useQueryClient } from '@tanstack/react-query'
import QRCode from 'qrcode'
import { apiErrorMessage, hostApi } from '../api/hostClient'
import { guestLink } from '../format'
import { qk, useEvent, useStyleLock } from '../queries'
import { copyText, ErrorBox, Icon, icons, CenterSpinner, shareLink, toast, ToastHost, TopBar } from '../ui'
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
  const navigate = useNavigate()
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
  const lock = useStyleLock()
  const choose = (p: QrPreset) => {
    if (lock.qrLocked(p, event.data?.settings.qr_style)) { toast('Дополнительные стили доступны с подпиской «Плюс»'); navigate('/app/plus'); return }
    setLocal(p); save.mutate(p)
  }

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

  const accent = { color: 'var(--dr-amber)' }
  const outline = {
    flex: 1, height: 52, borderRadius: 16, border: '1px solid rgba(255,179,71,.25)', background: 'rgba(255,179,71,.05)',
    color: 'var(--dr-text)', fontFamily: 'Manrope, sans-serif', fontWeight: 600, fontSize: 14, cursor: 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
  } as const

  return (
    <div className="darkroom" style={{ minHeight: '100dvh' }}>
      <div style={{ maxWidth: 440, margin: '0 auto', padding: 'calc(16px + env(safe-area-inset-top)) 20px 40px', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
        <div style={{ width: '100%', display: 'flex', alignItems: 'center', justifyContent: 'space-between' }}>
          <button onClick={() => navigate(`/app/events/${id}`)} aria-label="Закрыть"
            style={{ width: 40, height: 40, borderRadius: '50%', border: 'none', background: 'rgba(255,255,255,.08)', color: 'var(--dr-text)', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icon d={icons.close} />
          </button>
          <span className="host-edge" style={{ ...accent, letterSpacing: '.2em' }}>{event.data.title}</span>
          <span style={{ width: 40 }} />
        </div>

        <h1 style={{ fontFamily: "'PT Serif', serif", fontWeight: 400, fontSize: 26, textAlign: 'center', margin: '8px 0 0' }}>{event.data.title}</h1>

        <div style={{
          background: style.canvas, borderRadius: 28, padding: 22, width: '100%', maxWidth: 360,
          boxShadow: `0 0 60px ${style.glow}`, color: style.modules, textAlign: 'center',
        }}>
          <canvas ref={canvasRef} width={SIZE} height={SIZE} style={{ width: '100%', height: 'auto', display: 'block' }} aria-label={`QR-код альбома ${event.data.title}`} />
        </div>

        <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 14, wordBreak: 'break-all', textAlign: 'center', padding: '10px 18px', borderRadius: 999, border: '1px solid rgba(255,179,71,.3)', ...accent }}>{url}</div>
        <p style={{ textAlign: 'center', maxWidth: 340, fontSize: 14, color: 'rgba(240,230,210,.7)', lineHeight: 1.5, margin: 0 }}>
          Отправьте QR-код или ссылку гостям. Открыв страницу, они сразу начнут съёмку, ставить приложение не нужно.
        </p>

        <div style={{ display: 'flex', gap: 8, width: '100%' }}>
          <button style={outline} onClick={() => void copyText(url, 'Ссылка скопирована')}><Icon d={icons.copy} size={16} /> Скопировать</button>
          <button style={outline} onClick={() => void shareLink(url, event.data!.title)}><Icon d={icons.share} size={16} /> Поделиться</button>
          <button style={{ ...outline, flex: '0 0 76px' }} onClick={download}><Icon d={icons.download} size={16} /> PNG</button>
        </div>

        <div style={{ width: '100%' }}>
          <div className="host-field-label" style={{ color: 'rgba(240,230,210,.6)' }}>Стиль QR-кода</div>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: 8 }}>
            {(Object.keys(QR_PRESETS) as QrPreset[]).map((p) => (
              <button key={p} onClick={() => choose(p)} aria-pressed={preset === p}
                style={{
                  background: QR_PRESETS[p].canvas, color: QR_PRESETS[p].modules, borderRadius: 14, height: 64, cursor: 'pointer',
                  border: preset === p ? '2px solid var(--dr-amber)' : '2px solid transparent', fontSize: 12, fontWeight: 600, fontFamily: 'Manrope, sans-serif',
                }}>{QR_PRESETS[p].label}{lock.qrLocked(p, event.data?.settings.qr_style) ? ' 🔒' : ''}</button>
            ))}
          </div>
        </div>
      </div>
      <ToastHost />
    </div>
  )
}
