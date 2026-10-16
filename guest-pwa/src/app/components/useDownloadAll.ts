import { useState } from 'react'
import { apiErrorMessage, hostApi, type Schemas } from '../api/hostClient'
import { toast } from '../ui'

/** Сборка ZIP со всеми кадрами альбома: опрос задания каждые 2 с, затем скачивание. */
export function useDownloadAll(eventId: string) {
  const [downloading, setDownloading] = useState(false)

  const downloadAll = async () => {
    if (downloading) return
    setDownloading(true)
    try {
      const { data: job } = await hostApi.post<Schemas['ArchiveJobOut']>(`/events/${eventId}/download`)
      for (let i = 0; i < 90; i++) {
        await new Promise((r) => setTimeout(r, 2000))
        const { data } = await hostApi.get<Schemas['ArchiveJobOut']>(`/events/${eventId}/download/${job.job_id}`)
        if (data.status === 'ready' && data.download_url) { window.location.assign(data.download_url); return }
        if (data.status === 'empty') { toast('В альбоме пока нет фото'); return }
        if (data.status === 'failed') { toast('Не удалось собрать архив'); return }
      }
      toast('Архив собирается слишком долго, попробуйте позже')
    } catch (e) {
      toast(apiErrorMessage(e))
    } finally {
      setDownloading(false)
    }
  }

  return { downloading, downloadAll }
}
