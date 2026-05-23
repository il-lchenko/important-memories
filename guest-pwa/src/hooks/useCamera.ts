import { useRef, useEffect, useCallback, useState } from 'react'

export function useCamera() {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [ready, setReady] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const streamRef = useRef<MediaStream | null>(null)

  const start = useCallback(async (
    facingMode: 'environment' | 'user' = 'environment',
    targetRatio: number = 3 / 4,
  ) => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop())
    }
    const portrait = targetRatio <= 1
    const constraints: MediaStreamConstraints[] = [
      // 1st try: exact facingMode + resolution
      { video: { facingMode, width: { ideal: portrait ? 1080 : 1920 }, height: { ideal: portrait ? 1920 : 1080 }, aspectRatio: { ideal: targetRatio } }, audio: false },
      // 2nd try: facingMode only (no resolution constraints)
      { video: { facingMode }, audio: false },
      // 3rd try: any camera
      { video: true, audio: false },
    ]
    for (const c of constraints) {
      try {
        const stream = await navigator.mediaDevices.getUserMedia(c)
        streamRef.current = stream
        if (videoRef.current) {
          videoRef.current.srcObject = stream
          await videoRef.current.play()
        }
        setReady(true)
        setError(null)
        return
      } catch (_) { /* try next */ }
    }
    setError('Нет доступа к камере. Разрешите использование камеры в настройках браузера.')
    setReady(false)
  }, [])

  const stop = useCallback(() => {
    streamRef.current?.getTracks().forEach((t) => t.stop())
    streamRef.current = null
    setReady(false)
  }, [])

  /**
   * Capture a center-cropped frame matching targetRatio (w/h).
   * Default 3/4 = portrait. Pass 4/3 for landscape.
   */
  const capture = useCallback((
    targetRatio: number = 3 / 4,
  ): Promise<{ blob: Blob; width: number; height: number } | null> => {
    const video = videoRef.current
    if (!video) return Promise.resolve(null)

    const vw = video.videoWidth
    const vh = video.videoHeight

    // Center-crop to targetRatio
    let sw: number, sh: number, sx: number, sy: number
    if (vw / vh > targetRatio) {
      sh = vh
      sw = Math.round(vh * targetRatio)
      sx = Math.round((vw - sw) / 2)
      sy = 0
    } else {
      sw = vw
      sh = Math.round(vw / targetRatio)
      sx = 0
      sy = Math.round((vh - sh) / 2)
    }

    const canvas = document.createElement('canvas')
    canvas.width = sw
    canvas.height = sh
    canvas.getContext('2d')!.drawImage(video, sx, sy, sw, sh, 0, 0, sw, sh)

    return new Promise((resolve) => {
      canvas.toBlob((b) => resolve(b ? { blob: b, width: sw, height: sh } : null), 'image/jpeg', 0.92)
    })
  }, [])

  useEffect(() => () => stop(), [stop])

  return { videoRef, ready, error, start, stop, capture }
}
