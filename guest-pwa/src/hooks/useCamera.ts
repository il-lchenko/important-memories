import { useRef, useEffect, useCallback, useState } from 'react'
import { applyFilmLUT } from '../utils/filmLut'

export function useCamera() {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [ready, setReady] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [torchSupported, setTorchSupported] = useState(false)
  const [torchOn, setTorchOn] = useState(false)
  const streamRef = useRef<MediaStream | null>(null)

  const start = useCallback(async (
    facingMode: 'environment' | 'user' = 'environment',
  ) => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop())
    }
    const constraints: MediaStreamConstraints[] = [
      { video: { facingMode }, audio: false },
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
        // Detect torch (Android Chrome only — iOS Safari doesn't expose it)
        try {
          const track = stream.getVideoTracks()[0]
          const caps = (track.getCapabilities?.() ?? {}) as MediaTrackCapabilities & { torch?: boolean }
          setTorchSupported(Boolean(caps.torch))
        } catch { setTorchSupported(false) }
        setTorchOn(false)
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
    setTorchOn(false)
  }, [])

  const setTorch = useCallback(async (on: boolean) => {
    const track = streamRef.current?.getVideoTracks()[0]
    if (!track) return false
    try {
      await track.applyConstraints({ advanced: [{ torch: on } as MediaTrackConstraintSet & { torch: boolean }] })
      setTorchOn(on)
      return true
    } catch { return false }
  }, [])

  /**
   * Capture a center-cropped frame matching targetRatio (w/h).
   * Default 3/4 = portrait. Pass 4/3 for landscape.
   * Pass mirror=true for front camera to match preview appearance.
   * Auto-rotates when the raw stream orientation differs from the target.
   * Applies film LUT to the canvas before encoding — 'original' = no filter.
   */
  const capture = useCallback(async (
    targetRatio: number = 3 / 4,
    mirror: boolean = false,
    lutPreset: string = 'original',
  ): Promise<{ blob: Blob; width: number; height: number } | null> => {
    const video = videoRef.current
    if (!video) return null

    const vw = video.videoWidth
    const vh = video.videoHeight

    const streamIsLandscape = vw > vh
    const targetIsLandscape = targetRatio > 1
    const needsRotation = streamIsLandscape !== targetIsLandscape

    // sw = final canvas width, sh = final canvas height (in target orientation)
    let sw: number, sh: number

    if (needsRotation) {
      // Compute crop as if stream were already rotated (swap vw/vh)
      const rvw = vh
      const rvh = vw
      if (rvw / rvh > targetRatio) {
        sh = rvh
        sw = Math.round(rvh * targetRatio)
      } else {
        sw = rvw
        sh = Math.round(rvw / targetRatio)
      }
    } else {
      if (vw / vh > targetRatio) {
        sh = vh
        sw = Math.round(vh * targetRatio)
      } else {
        sw = vw
        sh = Math.round(vw / targetRatio)
      }
    }

    const canvas = document.createElement('canvas')
    canvas.width = sw
    canvas.height = sh
    const ctx = canvas.getContext('2d')!

    if (needsRotation) {
      // Crop a landscape region from the stream (sh wide × sw tall) then rotate 90°
      const cropW = sh
      const cropH = sw
      const origSx = Math.round((vw - cropW) / 2)
      const origSy = Math.round((vh - cropH) / 2)
      if (mirror) {
        // Rotate 90° CCW — equivalent to CW + horizontal flip for front camera
        ctx.translate(0, sh)
        ctx.rotate(-Math.PI / 2)
      } else {
        // Rotate 90° CW
        ctx.translate(sw, 0)
        ctx.rotate(Math.PI / 2)
      }
      ctx.drawImage(video, origSx, origSy, cropW, cropH, 0, 0, cropW, cropH)
    } else {
      // Stream and target orientations match — plain center-crop
      let sx: number, sy: number
      if (vw / vh > targetRatio) {
        sx = Math.round((vw - sw) / 2)
        sy = 0
      } else {
        sx = 0
        sy = Math.round((vh - sh) / 2)
      }
      if (mirror) {
        ctx.translate(sw, 0)
        ctx.scale(-1, 1)
      }
      ctx.drawImage(video, sx, sy, sw, sh, 0, 0, sw, sh)
    }

    // Apply film LUT to canvas pixels before encoding
    ctx.setTransform(1, 0, 0, 1, 0, 0)
    await applyFilmLUT(ctx, sw, sh, lutPreset)

    return await new Promise<{ blob: Blob; width: number; height: number } | null>((resolve) => {
      canvas.toBlob((b) => resolve(b ? { blob: b, width: sw, height: sh } : null), 'image/jpeg', 0.92)
    })
  }, [])

  useEffect(() => () => stop(), [stop])

  return { videoRef, ready, error, start, stop, capture, torchSupported, torchOn, setTorch }
}
