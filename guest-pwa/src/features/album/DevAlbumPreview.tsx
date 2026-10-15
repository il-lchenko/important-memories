import { useMemo, useRef } from 'react'
import type { Frame, ViewMode } from './AlbumScreen'
import { DesktopAlbum } from './PublicAlbumScreen'
import { useState } from 'react'

const SAMPLE_IMAGES = [
  'https://images.unsplash.com/photo-1519741497674-611481863552?w=800',
  'https://images.unsplash.com/photo-1511285560929-80b456fea0bc?w=800',
  'https://images.unsplash.com/photo-1522673607200-164d1b6ce486?w=800',
  'https://images.unsplash.com/photo-1529636798458-92182e662485?w=800',
  'https://images.unsplash.com/photo-1465495976277-4387d4b0e4a6?w=800',
  'https://images.unsplash.com/photo-1519225421980-715cb0215aed?w=800',
  'https://images.unsplash.com/photo-1511795409834-ef04bbd61622?w=800',
  'https://images.unsplash.com/photo-1464366400600-7168b8af9bc3?w=800',
  'https://images.unsplash.com/photo-1507504031003-b417219a0fde?w=800',
  'https://images.unsplash.com/photo-1511795409834-432f31197ce4?w=800',
  'https://images.unsplash.com/photo-1532712938310-34cb3982ef74?w=800',
  'https://images.unsplash.com/photo-1485872299712-c22086df3e7e?w=800',
  'https://images.unsplash.com/photo-1527529482837-4698179dc6ce?w=800',
  'https://images.unsplash.com/photo-1522327646852-4e28586a40dd?w=800',
  'https://images.unsplash.com/photo-1510076857177-7470076d4098?w=800',
  'https://images.unsplash.com/photo-1529333166437-7750a6dd5a70?w=800',
]

const NAMES = ['Аня', 'Макс', 'Соня', 'Егор', 'Лиза', 'Дима', 'Нина', 'Паша']
const AVATARS: (string | null)[] = [
  'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=120&h=120&fit=crop&crop=faces',
  'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=120&h=120&fit=crop&crop=faces',
  null,
  'https://images.unsplash.com/photo-1522075469751-3a6694fb2f61?w=120&h=120&fit=crop&crop=faces',
  'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=120&h=120&fit=crop&crop=faces',
  null,
  null,
  'https://images.unsplash.com/photo-1573496359142-b8d87734a5a2?w=120&h=120&fit=crop&crop=faces',
]
const CAPTIONS = [
  'Самый важный момент',
  '',
  'Первый тост',
  'С друзьями',
  '',
  'Браво жениху',
  'Вот это улыбка!',
  '',
  'Запомни этот день',
  'Танцы до утра',
  '',
  'Торт был вкуснейший',
  '',
  'Это было прекрасно',
  'Семейное фото',
  '',
]

export default function DevAlbumPreview() {
  const frames: Frame[] = useMemo(
    () =>
      SAMPLE_IMAGES.map((url, i) => ({
        id: `f-${i}`,
        guest_id: `g-${i % NAMES.length}`,
        guest_name: NAMES[i % NAMES.length],
        captured_at: new Date(Date.now() - i * 3600_000).toISOString(),
        thumbnail_url: url,
        preview_url: url,
        full_url: url,
        width: 800,
        height: 1067,
        is_mine: false,
        caption: CAPTIONS[i] || undefined,
        note: i === 0
          ? 'Этот момент запомнил весь день. Жених нёс невесту на руках через пол-зала, а шары поднимались выше свечей. Казалось, время остановилось.'
          : (i === 4 ? 'Папа говорил, что никогда не плачет на свадьбах. Соврал.' : null),
        source: i === 2 || i === 7 ? 'upload' : 'camera',
        guest_avatar_url: AVATARS[i % NAMES.length],
      })),
    [],
  )

  const [mode, setMode] = useState<ViewMode>('magazine')
  const sentinel = useRef<HTMLDivElement>(null)
  const uniqAuthors = useMemo(() => new Set(frames.map((f) => f.guest_id)).size, [frames])

  return (
    <DesktopAlbum
      meta={{ title: 'Свадьба Ани и Макса', id: 'preview' }}
      frames={frames}
      loading={false}
      loadingMore={false}
      totalFrames={frames.length}
      authorCount={uniqAuthors}
      mode={mode}
      onModeChange={setMode}
      onOpenFrame={(i) => alert(`open frame ${i}`)}
      onShare={() => alert('share (preview)')}
      sentinelRef={sentinel}
    />
  )
}
