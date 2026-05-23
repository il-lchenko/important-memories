interface Props {
  onRetry: () => void
}

export default function OfflineScreen({ onRetry }: Props) {
  return (
    <div style={{
      minHeight: '100dvh',
      background: 'var(--paper)',
      display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: '32px 24px', textAlign: 'center',
    }}>
      {/* No-wifi icon */}
      <div style={{
        width: 80, height: 80, borderRadius: 40,
        background: 'var(--paper-3)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        marginBottom: 24,
      }}>
        <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="var(--ink-3)" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <line x1="1" y1="1" x2="23" y2="23" />
          <path d="M16.72 11.06A10.94 10.94 0 0 1 19 12.55" />
          <path d="M5 12.55a10.94 10.94 0 0 1 5.17-2.39" />
          <path d="M10.71 5.05A16 16 0 0 1 22.56 9" />
          <path d="M1.42 9a15.91 15.91 0 0 1 4.7-2.88" />
          <path d="M8.53 16.11a6 6 0 0 1 6.95 0" />
          <circle cx="12" cy="20" r="1" fill="var(--ink-3)" stroke="none" />
        </svg>
      </div>

      <h2 style={{
        fontFamily: 'Fraunces, serif', fontStyle: 'italic',
        fontSize: 24, fontWeight: 500, color: 'var(--ink)',
        margin: '0 0 8px',
      }}>
        Нет подключения
      </h2>

      <p style={{
        fontFamily: 'Inter, sans-serif', fontSize: 14,
        color: 'var(--ink-3)', lineHeight: 1.6,
        maxWidth: 260, margin: '0 0 40px',
      }}>
        Проверьте интернет и попробуйте снова.
        Снятые фото не потеряются.
      </p>

      <button
        className="btn-primary"
        style={{ maxWidth: 280 }}
        onClick={onRetry}
      >
        Повторить
      </button>
    </div>
  )
}
