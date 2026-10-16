import { useRef, useState, type ReactNode } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { guestApi, uploadPutBlob } from '../../api/client'
import { apiErrorMessage } from '../api/hostClient'
import { startOwnerCamera } from '../ownerCamera'
import { qk } from '../queries'
import { toast } from '../ui'

const MAX_FILES = 30

async function sha256Hex(file: File): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', await file.arrayBuffer())
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('')
}

function mimeOf(file: File): string {
  if (file.type) return file.type
  const n = file.name.toLowerCase()
  if (n.endsWith('.heic')) return 'image/heic'
  if (n.endsWith('.heif')) return 'image/heif'
  if (n.endsWith('.png')) return 'image/png'
  if (n.endsWith('.webp')) return 'image/webp'
  return 'image/jpeg'
}

async function dimensions(file: File): Promise<{ w: number; h: number }> {
  try {
    const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' })
    const d = { w: bmp.width, h: bmp.height }
    bmp.close?.()
    return d
  } catch {
    return { w: 1000, h: 1000 } // HEIC без декодера в браузере: точный размер сервер уточнит при обработке
  }
}

/** Добавление фото из галереи в свой альбом (событие или соло): от владельца разрешено всегда. */
export function useGalleryUpload(eventId: string, shortCode: string, displayName: string): {
  pick: () => void
  busy: boolean
  progress: string | null
  input: ReactNode
} {
  const qc = useQueryClient()
  const ref = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const [progress, setProgress] = useState<string | null>(null)

  const run = async (files: File[]) => {
    setBusy(true)
    let done = 0
    let failed = 0
    let lastError: unknown = null
    try {
      await startOwnerCamera(shortCode, displayName)
      for (let i = 0; i < files.length; i++) {
        setProgress(`${i + 1} из ${files.length}`)
        const file = files[i]
        try {
          const hash = await sha256Hex(file)
          const { data: presign } = await guestApi.presign(file.size, mimeOf(file), { source: 'upload', uploadHash: hash })
          if (!presign.deduplicated) {
            await uploadPutBlob(presign.upload_url, file, new AbortController().signal)
          }
          const { w, h } = await dimensions(file)
          await guestApi.registerFrame(presign.frame_id, new Date().toISOString(), w, h, { source: 'upload' })
          done++
        } catch (e) {
          failed++
          lastError = e
        }
      }
    } catch (e) {
      lastError = e
      failed = files.length - done
    } finally {
      setBusy(false)
      setProgress(null)
      void qc.invalidateQueries({ queryKey: qk.event(eventId) })
      void qc.invalidateQueries({ queryKey: qk.album(eventId) })
      void qc.invalidateQueries({ queryKey: qk.events })
      void qc.invalidateQueries({ queryKey: qk.entitlements })
    }
    if (done > 0 && failed === 0) toast(done === 1 ? 'Фото добавлено, обрабатываем' : `Добавлено фото: ${done}, обрабатываем`)
    else if (done > 0) toast(`Добавлено ${done}, не удалось ${failed}`)
    else toast(apiErrorMessage(lastError, 'Не удалось добавить фото'))
  }

  const input = (
    <input
      ref={ref}
      type="file"
      accept="image/*,.heic,.heif"
      multiple
      hidden
      onChange={(ev) => {
        const list = Array.from(ev.target.files ?? []).slice(0, MAX_FILES)
        ev.target.value = ''
        if (list.length) void run(list)
      }}
    />
  )

  return { pick: () => { if (!busy) ref.current?.click() }, busy, progress, input }
}
