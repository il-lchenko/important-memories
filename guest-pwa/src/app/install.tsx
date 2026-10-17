import { useEffect, useState, type ReactNode } from 'react'

/* Установка веб-версии на телефон: Android/Chrome даёт системный запрос, iPhone (Safari) ставится вручную через «Поделиться». */

interface InstallEvent extends Event {
  prompt: () => Promise<void>
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>
}

let deferred: InstallEvent | null = null
const listeners = new Set<() => void>()

/** Вызывается один раз при старте раздела: запоминаем системный запрос установки, пока браузер его не потерял. */
export function captureInstallPrompt() {
  window.addEventListener('beforeinstallprompt', (e) => {
    e.preventDefault()
    deferred = e as InstallEvent
    listeners.forEach((l) => l())
  })
  window.addEventListener('appinstalled', () => {
    deferred = null
    listeners.forEach((l) => l())
  })
}

export function isStandalone(): boolean {
  return window.matchMedia('(display-mode: standalone)').matches || (navigator as unknown as { standalone?: boolean }).standalone === true
}

export type Platform = 'ios' | 'android' | 'desktop'
export function detectPlatform(): Platform {
  const ua = navigator.userAgent
  if (/iPhone|iPad|iPod/.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'ios'
  if (/Android/.test(ua)) return 'android'
  return 'desktop'
}

/** Во встроенных браузерах (Telegram, Instagram и др.) установка недоступна: нужен Safari или Chrome. */
export function isInAppBrowser(): boolean {
  return /FBAN|FBAV|Instagram|Telegram|VKClient|OKApp|Line\/|; wv\)/i.test(navigator.userAgent)
}

export function useInstall() {
  const [, bump] = useState(0)
  useEffect(() => {
    const l = () => bump((n) => n + 1)
    listeners.add(l)
    return () => { listeners.delete(l) }
  }, [])
  return {
    standalone: isStandalone(),
    canPrompt: deferred !== null,
    prompt: async () => {
      if (!deferred) return false
      await deferred.prompt()
      const choice = await deferred.userChoice
      deferred = null
      listeners.forEach((x) => x())
      return choice.outcome === 'accepted'
    },
  }
}

function Num({ n }: { n: number }) {
  return (
    <span style={{ width: 26, height: 26, borderRadius: '50%', background: 'var(--amber)', color: '#fff', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontWeight: 700, fontSize: 13, flexShrink: 0 }}>{n}</span>
  )
}

function ShareGlyph() {
  return (
    <svg width="18" height="18" viewBox="0 0 24 24" aria-hidden="true" style={{ verticalAlign: '-3px' }}>
      <path d="M12 3v12M8 7l4-4 4 4M5 11v8a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-8" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

/** Подсказка «как поставить на телефон» под нужную платформу. */
export function InstallGuide({ compact = false }: { compact?: boolean }) {
  const install = useInstall()
  const platform = detectPlatform()
  const [done, setDone] = useState(false)

  if (install.standalone) {
    return <p className="host-muted" style={{ margin: 0 }}>Приложение уже установлено на это устройство.</p>
  }

  let body: ReactNode
  if (isInAppBrowser()) {
    body = <p style={{ margin: 0, lineHeight: 1.5 }}>Вы открыли сайт внутри другого приложения. Откройте эту страницу в {platform === 'ios' ? 'Safari' : 'Chrome'}: там появится установка.</p>
  } else if (install.canPrompt) {
    body = (
      <>
        <p style={{ margin: '0 0 12px', lineHeight: 1.5 }}>Значок появится на экране, а ImpoMento откроется без адресной строки, как обычное приложение.</p>
        <button className="btn" disabled={done} onClick={async () => { if (await install.prompt()) setDone(true) }}>
          {done ? 'Установлено' : 'Установить приложение'}
        </button>
      </>
    )
  } else if (platform === 'ios') {
    body = (
      <ol style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 10, lineHeight: 1.45 }}>
        <li style={{ display: 'flex', gap: 10 }}><Num n={1} /><span>Откройте сайт в <b>Safari</b> и нажмите <b>«Поделиться»</b> <ShareGlyph /> внизу экрана.</span></li>
        <li style={{ display: 'flex', gap: 10 }}><Num n={2} /><span>Прокрутите список и выберите <b>«На экран “Домой”»</b>.</span></li>
        <li style={{ display: 'flex', gap: 10 }}><Num n={3} /><span>Нажмите <b>«Добавить»</b>. Значок ImpoMento появится среди приложений.</span></li>
      </ol>
    )
  } else if (platform === 'android') {
    body = (
      <ol style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 10, lineHeight: 1.45 }}>
        <li style={{ display: 'flex', gap: 10 }}><Num n={1} /><span>Откройте меню браузера <b>⋮</b> в правом верхнем углу.</span></li>
        <li style={{ display: 'flex', gap: 10 }}><Num n={2} /><span>Выберите <b>«Установить приложение»</b> или <b>«Добавить на главный экран»</b>.</span></li>
        <li style={{ display: 'flex', gap: 10 }}><Num n={3} /><span>Подтвердите. Значок появится на экране телефона.</span></li>
      </ol>
    )
  } else {
    body = <p style={{ margin: 0, lineHeight: 1.5 }}>В адресной строке Chrome или Edge нажмите значок установки справа, либо откройте меню браузера и выберите «Установить ImpoMento».</p>
  }
  return <div style={{ fontSize: compact ? 14 : 15 }}>{body}</div>
}
