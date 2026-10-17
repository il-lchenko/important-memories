import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { Tour, markTourSeen, tourSeen, type TourStep } from './components/Tour'
import { isStandalone } from './install'

const HOW: TourStep['extra'] = (
  <ol className="tour-steps">
    <li><span className="n">1</span><span><b>Создайте событие</b> и выберите плёнку.</span></li>
    <li><span className="n">2</span><span><b>Покажите гостям QR-код.</b> Они снимают в браузере, без установки.</span></li>
    <li><span className="n">3</span><span><b>Откройте альбом</b> после проявки: все кадры в одном месте.</span></li>
  </ol>
)

/** Первый вход: что есть в разделе «Альбомы», затем как поставить на телефон. */
export function AlbumsTour({ ready }: { ready: boolean }) {
  const navigate = useNavigate()
  const [open, setOpen] = useState(false)
  useEffect(() => {
    if (!ready || tourSeen('albums')) return
    const t = window.setTimeout(() => setOpen(true), 900)
    return () => window.clearTimeout(t)
  }, [ready])
  if (!open) return null

  const steps: TourStep[] = [
    { kind: 'welcome', title: 'Добро пожаловать в ImpoMento', text: 'Одноразовая камера для праздников. Гости снимают по QR-коду, а все кадры собираются в одном альбоме. Покажем, где что находится.' },
    { target: 'new', title: 'Новый альбом', text: 'Здесь всё начинается. Выберите: событие с гостями, личный соло-альбом или подборку лучших кадров.' },
    { target: 'filters', title: 'Ваши альбомы', text: 'Переключайте разделы: события, соло, подборки и альбомы, где вы гость. Ниже поиск и фильтры по статусу.' },
    { target: 'tab-frames', title: 'Кадры', text: 'Лучшие кадры из всех ваших альбомов собираются здесь сами. Из них можно составить мини-альбомы.' },
    { target: 'tab-profile', title: 'Профиль', text: 'Подписка «Плюс», промокоды, приглашение друзей и настройки аккаунта. Подсказки можно включить снова.' },
    ...(isStandalone() ? [] : [{ kind: 'install' as const, title: 'Поставьте на телефон' }]),
    { kind: 'finish', title: 'Как это работает', extra: HOW, cta: { label: 'Создать альбом', run: () => navigate('/app/new') } },
  ]
  return <Tour steps={steps} onClose={() => { markTourSeen('albums'); setOpen(false) }} />
}

/** Первое открытие события: где обложка, QR, проявка и настройки. */
export function EventTour({ ready, draft }: { ready: boolean; draft: boolean }) {
  const [open, setOpen] = useState(false)
  useEffect(() => {
    if (!ready || tourSeen('event') || !tourSeen('albums')) return
    const t = window.setTimeout(() => setOpen(true), 900)
    return () => window.clearTimeout(t)
  }, [ready])
  if (!open) return null

  const cover = { target: 'cover', title: 'Обложка', text: 'Загрузите фото, возьмите первый кадр или выберите из снятых. Обложку можно сменить в любой момент.' }
  const settings = { target: 'settings', title: 'Настройки', text: 'Плёнка, время проявки, число гостей и кадров, ссылка для просмотра.' }
  const steps: TourStep[] = draft
    ? [
        cover,
        { target: 'launch', title: 'Запуск', text: 'Запустите событие, и появится QR-код для гостей. До запуска снимать нельзя.' },
        settings,
      ]
    : [
        cover,
        { target: 'qr', title: 'QR-код для гостей', text: 'Покажите его на празднике. Гости сканируют код и снимают на ваш альбом, ничего устанавливать не нужно.' },
        { target: 'camera', title: 'Снимайте сами', text: 'Вы тоже можете снимать в этом альбоме. Снимки из галереи добавляются строкой выше.' },
        { target: 'reveal', title: 'Проявка', text: 'До проявки гости не видят чужие кадры. Откройте альбом вручную или задайте таймер в настройках.' },
        settings,
      ]
  return <Tour steps={steps} onClose={() => { markTourSeen('event'); setOpen(false) }} />
}
