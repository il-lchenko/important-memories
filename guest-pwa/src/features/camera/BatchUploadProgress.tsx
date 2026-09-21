interface Props {
  total: number
  done: number
  failed: number
}

/**
 * Overlay поверх камеры на время gallery-upload батча.
 * Показывает прогресс + сноску о правах (см. project_upload_from_gallery.md,
 * подтверждение прав встроено в UI вместо отдельной модалки).
 */
export default function BatchUploadProgress({ total, done, failed }: Props) {
  const remaining = Math.max(0, total - done - failed)
  const percent = total > 0 ? Math.round(((done + failed) / total) * 100) : 0
  const finished = remaining === 0

  return (
    <div style={{
      position: 'fixed', inset: 0, zIndex: 100,
      background: 'rgba(0,0,0,0.55)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: '0 20px',
      backdropFilter: 'blur(2px)',
      WebkitBackdropFilter: 'blur(2px)',
    }}>
      <div style={{
        width: '100%', maxWidth: 360,
        background: '#1F1712',
        border: '1px solid rgba(255,179,71,0.15)',
        borderRadius: 20,
        padding: '26px 22px 22px',
        textAlign: 'center',
        boxShadow: '0 20px 60px rgba(0,0,0,0.5)',
      }}>
        <div style={{
          width: 56, height: 56, borderRadius: 16,
          background: finished ? '#6A9269' : 'rgba(255,179,71,0.15)',
          color: finished ? '#fff' : '#FFB347',
          display: 'grid', placeItems: 'center',
          margin: '0 auto 14px',
        }}>
          {finished ? (
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
              <path d="M20 6L9 17l-5-5"/>
            </svg>
          ) : (
            <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
              <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/>
              <polyline points="17 8 12 3 7 8"/>
              <line x1="12" y1="3" x2="12" y2="15"/>
            </svg>
          )}
        </div>

        <div style={{
          fontFamily: 'Fraunces, serif',
          fontSize: 20, fontWeight: 600,
          color: '#FFB347',
          marginBottom: 6,
          letterSpacing: '-0.3px',
        }}>
          {finished ? `Загружено ${done} из ${total}` : 'Отправляем фото'}
        </div>
        <div style={{ fontSize: 13, color: 'rgba(255,179,71,0.55)', marginBottom: 18 }}>
          {finished
            ? 'Плёночный фильтр применится в течение нескольких секунд'
            : 'Плёночный фильтр применится на сервере'}
        </div>

        {/* Progress bar */}
        <div style={{
          height: 6, borderRadius: 3,
          background: 'rgba(255,179,71,0.15)',
          overflow: 'hidden',
          marginBottom: 8,
        }}>
          <div style={{
            width: `${percent}%`, height: '100%',
            background: finished ? '#6A9269' : '#FFB347',
            borderRadius: 3,
            transition: 'width 0.25s ease',
          }} />
        </div>
        <div style={{
          fontSize: 12, color: 'rgba(255,179,71,0.65)', letterSpacing: 0.5,
          fontVariantNumeric: 'tabular-nums',
          marginBottom: failed > 0 ? 4 : 18,
        }}>
          {done + failed} / {total}
        </div>
        {failed > 0 && (
          <div style={{ fontSize: 11, color: '#D54B3D', marginBottom: 14 }}>
            {failed} не удалось отправить
          </div>
        )}

        {/* Text о правах — вместо модалки, «как Facebook». */}
        <div style={{
          fontSize: 11,
          color: 'rgba(255,179,71,0.45)',
          lineHeight: 1.5,
          padding: '0 4px',
        }}>
          Отправляя, вы подтверждаете, что&nbsp;имеете право использовать эти&nbsp;фото.
        </div>
      </div>
    </div>
  )
}
