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
    // Поток всегда просим в 4:3. Поток 16:9 (4K/1080p) на большинстве телефонов — это
    // обрезка сенсора по короткой стороне: превью выглядит «приближенным» и уже, чем
    // в обычной камере и чем итоговое фото (takePhoto отдаёт полный кадр 4:3).
    // Полноразмерный снимок берётся отдельно через ImageCapture.takePhoto.
    const isFront = facingMode === 'user'
    const mk = (w: number, h: number): MediaStreamConstraints => ({
      video: { facingMode, width: { ideal: w }, height: { ideal: h }, aspectRatio: { ideal: 4 / 3 } },
      audio: false,
    })
    const constraints: MediaStreamConstraints[] = isFront
      ? [mk(1920, 1440), mk(1280, 960), { video: { facingMode }, audio: false }, { video: true, audio: false }]
      : [mk(2592, 1944), mk(1920, 1440), mk(1280, 960), { video: { facingMode }, audio: false }, { video: true, audio: false }]
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

    // ImageCapture.takePhoto() — реальный snapshot с сенсора (не video frame).
    // grabFrame() возвращает лишь текущий кадр video-потока (motion blur, 30fps quality) —
    // это оказалось хуже. takePhoto() медленнее, но даёт настоящую фотографию.
    // Поддержка: Chrome/Firefox Android. Fallback на drawImage(video) для iOS Safari.
    let photoBitmap: ImageBitmap | null = null
    try {
      const track = streamRef.current?.getVideoTracks()[0]
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const IC = (globalThis as any).ImageCapture
      if (track && IC) {
        const ic = new IC(track)
        // Явно просим максимальное разрешение снимка: без этого часть браузеров отдаёт
        // уменьшенный размер по умолчанию.
        let photoSettings: Record<string, number> = {}
        try {
          const caps = await ic.getPhotoCapabilities()
          const mw = caps?.imageWidth?.max
          const mh = caps?.imageHeight?.max
          if (mw && mh) photoSettings = { imageWidth: mw, imageHeight: mh }
        } catch { /* настройки по умолчанию */ }
        const photoBlob: Blob | null = await ic.takePhoto(photoSettings).catch(() => ic.takePhoto().catch(() => null))
        if (photoBlob) {
          photoBitmap = await createImageBitmap(photoBlob).catch(() => null)
        }
      }
    } catch { /* fallback to video frame */ }

    const vw = photoBitmap?.width ?? video.videoWidth
    const vh = photoBitmap?.height ?? video.videoHeight

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
    // 'high' — bicubic resample, критично для качества при downscale больших фото.
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
      ctx.drawImage(photoBitmap ?? video, origSx, origSy, cropW, cropH, 0, 0, cropW, cropH)
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
      ctx.drawImage(photoBitmap ?? video, sx, sy, sw, sh, 0, 0, sw, sh)
    }

    // Apply film LUT to canvas pixels before encoding.
    // Работаем в реальных пикселях canvas (outW × outH), а не в scaled-координатах.
    ctx.setTransform(1, 0, 0, 1, 0, 0)
    await applyFilmLUT(ctx, outW, outH, lutPreset)

    // Освобождаем bitmap (иначе течёт память на серии кадров).
    if (photoBitmap) photoBitmap.close?.()

    return await new Promise<{ blob: Blob; width: number; height: number } | null>((resolve) => {
      // q=0.93: балансировка скорости и качества. Ниже 0.90 виден компрессионный
      // блочный артефакт («квадратно»); 0.95 медленнее и лишь чуть лучше.
      canvas.toBlob((b) => {
        resolve(b ? { blob: b, width: outW, height: outH } : null)
      }, 'image/jpeg', 0.93)
    })
  }, [])

  /**
   * Снимок из системной камеры телефона (input capture): качество и обработку даёт сама камера.
   * Рисуем через <img>: браузер сам применяет ориентацию из EXIF, а перекодирование на canvas
   * убирает из файла геометки и EXIF. Дальше только плёнка альбома и кодирование JPEG.
   */
  const processFile = useCallback(async (
    file: File,
    lutPreset: string = 'original',
  ): Promise<{ blob: Blob; width: number; height: number } | null> => {
    const url = URL.createObjectURL(file)
    try {
      const img = new Image()
      img.src = url
      await img.decode()
      let w = img.naturalWidth
      let h = img.naturalHeight
      if (!w || !h) return null
      const MAX_LONG_SIDE = 4000
      const scale = Math.max(w, h) > MAX_LONG_SIDE ? MAX_LONG_SIDE / Math.max(w, h) : 1
      w = Math.round(w * scale)
      h = Math.round(h * scale)
      const canvas = document.createElement('canvas')
      canvas.width = w
      canvas.height = h
      const ctx = canvas.getContext('2d')!
      ctx.imageSmoothingEnabled = true
      ctx.imageSmoothingQuality = 'high'
      ctx.drawImage(img, 0, 0, w, h)
      await applyFilmLUT(ctx, w, h, lutPreset)
      return await new Promise((resolve) => {
        canvas.toBlob((b) => resolve(b ? { blob: b, width: w, height: h } : null), 'image/jpeg', 0.93)
      })
    } catch {
      return null
    } finally {
      URL.revokeObjectURL(url)
    }
  }, [])

  useEffect(() => () => stop(), [stop])

  return {
    videoRef, ready, error, start, stop, capture, processFile,
    torchSupported, torchOn, setTorch,
    zoomSupported, minZoom, maxZoom, zoom, setZoom,
  }
}
