import { useRef, useEffect, useCallback, useState } from 'react'
import { applyFilmLUT } from '../utils/filmLut'

export function useCamera() {
  const videoRef = useRef<HTMLVideoElement>(null)
  const [ready, setReady] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const [torchSupported, setTorchSupported] = useState(false)
  const [torchOn, setTorchOn] = useState(false)
  // Hardware zoom: реальный zoom через MediaTrack constraints (не CSS transform).
  // Первые уровни (до 2-3x) на большинстве Android — оптика/sensor-crop, лучше качество.
  const [zoomSupported, setZoomSupported] = useState(false)
  const [minZoom, setMinZoom] = useState(1)
  const [maxZoom, setMaxZoom] = useState(1)
  const [zoom, setZoomState] = useState(1)
  const streamRef = useRef<MediaStream | null>(null)
  // Track latest gamma to determine CW vs CCW landscape rotation
  const gammaRef = useRef<number>(0)

  useEffect(() => {
    const handler = (e: DeviceOrientationEvent) => {
      if (e.gamma !== null) gammaRef.current = e.gamma
    }
    window.addEventListener('deviceorientation', handler, { passive: true })
    return () => window.removeEventListener('deviceorientation', handler)
  }, [])

  const start = useCallback(async (
    facingMode: 'environment' | 'user' = 'environment',
  ) => {
    if (streamRef.current) {
      streamRef.current.getTracks().forEach((t) => t.stop())
    }
    // Разные ideals для front/back — иначе фронталка не тянет 4K и падает
    // fallback-ом в 720p (юзер видит «плохое качество селфи»).
    // Для user (front): попросить 2560×1440 → 1920×1080 → без constraint (max сенсора).
    // Для environment (back): 4K → 3MP → без constraint.
    const isFront = facingMode === 'user'
    const constraints: MediaStreamConstraints[] = isFront
      ? [
          { video: { facingMode, width: { ideal: 2560 }, height: { ideal: 1440 } }, audio: false },
          { video: { facingMode, width: { ideal: 1920 }, height: { ideal: 1080 } }, audio: false },
          { video: { facingMode }, audio: false },
          { video: true, audio: false },
        ]
      : [
          { video: { facingMode, width: { ideal: 3840 }, height: { ideal: 2160 } }, audio: false },
          { video: { facingMode, width: { ideal: 2048 }, height: { ideal: 1536 } }, audio: false },
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
        // Detect torch + zoom capabilities (Android Chrome only — iOS Safari не отдаёт).
        try {
          const track = stream.getVideoTracks()[0]
          const caps = (track.getCapabilities?.() ?? {}) as MediaTrackCapabilities & {
            torch?: boolean; zoom?: { min: number; max: number; step: number }
          }
          setTorchSupported(Boolean(caps.torch))
          if (caps.zoom && caps.zoom.max > caps.zoom.min + 0.01) {
            setZoomSupported(true)
            setMinZoom(caps.zoom.min)
            setMaxZoom(caps.zoom.max)
            setZoomState(caps.zoom.min)
          } else {
            setZoomSupported(false)
            setMinZoom(1); setMaxZoom(1); setZoomState(1)
          }
        } catch { setTorchSupported(false); setZoomSupported(false) }
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

  // Устанавливает zoom реально в самой камере (не CSS-скейл на элементе).
  // На Android Chrome вызовет sensor-crop / оптический zoom (если есть tele-линза).
  const setZoom = useCallback(async (level: number) => {
    const track = streamRef.current?.getVideoTracks()[0]
    if (!track) return false
    try {
      const clamped = Math.max(minZoom, Math.min(maxZoom, level))
      await track.applyConstraints({
        advanced: [{ zoom: clamped } as MediaTrackConstraintSet & { zoom: number }],
      })
      setZoomState(clamped)
      return true
    } catch { return false }
  }, [minZoom, maxZoom])

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

    // Downscale к 4000 по длинной стороне — сохраняем ~12 Мп (полный размер камеры),
    // чтобы при скачивании фото было в высоком качестве. LUT-обработка в Web Worker.
    const MAX_LONG_SIDE = 4000
    const longer = Math.max(sw, sh)
    const scaleDown = longer > MAX_LONG_SIDE ? MAX_LONG_SIDE / longer : 1
    const outW = Math.round(sw * scaleDown)
    const outH = Math.round(sh * scaleDown)

    const canvas = document.createElement('canvas')
    canvas.width = outW
    canvas.height = outH
    const ctx = canvas.getContext('2d')!
    ctx.imageSmoothingEnabled = true
    ctx.imageSmoothingQuality = 'high'
    // scale ПЕРЕД translate/rotate: значения ниже пишутся в «оригинальных»
    // координатах (sw, sh, cropW, cropH), а браузер бесплатно ресайзит при выводе.
    if (scaleDown !== 1) ctx.scale(scaleDown, scaleDown)

    if (needsRotation) {
      // Crop a portrait region from the stream (cropW × cropH) then rotate to landscape
      const cropW = sh
      const cropH = sw
      const origSx = Math.round((vw - cropW) / 2)
      const origSy = Math.round((vh - cropH) / 2)
      if (mirror) {
        // Front camera: 90° CW rotation
        ctx.translate(sw, 0)
        ctx.rotate(Math.PI / 2)
      } else {
        // Back camera: determine CW vs CCW from device gamma.
        // gamma < 0 → phone rotated CW (right side down) → scene UP is at LEFT of stream → rotate 90° CW
        // gamma > 0 → phone rotated CCW (left side down) → scene UP is at RIGHT of stream → rotate 90° CCW
        if (gammaRef.current < 0) {
          // CW landscape (most common: right thumb up)
          ctx.translate(sw, 0)
          ctx.rotate(Math.PI / 2)
        } else {
          // CCW landscape
          ctx.translate(0, sh)
          ctx.rotate(-Math.PI / 2)
        }
      }
      ctx.drawImage(video, origSx, origSy, cropW, cropH, 0, 0, cropW, cropH)
    } else {
      // Stream и target ориентации совпадают — простой центр-кроп.
      // Раньше здесь была ветка isSecondaryLandscape с 180° поворотом
      // (через screen.orientation.type + gamma-fallback), но она давала
      // перевёрнутое фото в ОБОИХ landscape на Android Chrome — современный
      // браузер уже отдаёт видео в правильной ориентации для текущей физ.
      // ориентации устройства, дополнительный rotate только ломает результат.
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

    // Apply film LUT to canvas pixels before encoding.
    // Работаем в реальных пикселях canvas (outW × outH), а не в scaled-координатах.
    ctx.setTransform(1, 0, 0, 1, 0, 0)
    await applyFilmLUT(ctx, outW, outH, lutPreset)

    return await new Promise<{ blob: Blob; width: number; height: number } | null>((resolve) => {
      canvas.toBlob((b) => {
        resolve(b ? { blob: b, width: outW, height: outH } : null)
      }, 'image/jpeg', 0.92)
    })
  }, [])

  useEffect(() => () => stop(), [stop])

  return {
    videoRef, ready, error, start, stop, capture,
    torchSupported, torchOn, setTorch,
    zoomSupported, minZoom, maxZoom, zoom, setZoom,
  }
}
