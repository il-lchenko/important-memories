type CurvePoints = [number, number][]

function clamp(v: number): number {
  return v < 0 ? 0 : v > 255 ? 255 : v | 0
}

function buildCurve(points: CurvePoints): Uint8Array {
  const sorted = [...points].sort((a, b) => a[0] - b[0])
  const lut = new Uint8Array(256)
  for (let i = 0; i < 256; i++) {
    const x = i / 255
    let j = 0
    while (j < sorted.length - 1 && sorted[j + 1][0] < x) j++
    if (j >= sorted.length - 1) {
      lut[i] = Math.round(sorted[sorted.length - 1][1] * 255)
      continue
    }
    const [x0, y0] = sorted[j]
    const [x1, y1] = sorted[j + 1]
    const t = (x - x0) / (x1 - x0)
    const ts = t * t * (3 - 2 * t) // smoothstep
    lut[i] = clamp((y0 + (y1 - y0) * ts) * 255)
  }
  return lut
}

interface FilmPreset {
  r: CurvePoints
  g: CurvePoints
  b: CurvePoints
  saturation: number
  fade: number
  shadowTint: [number, number, number]
  highlightTint: [number, number, number]
  temperature: number
  grainStrength: number
  vignetteStrength: number
  halation?: number
  bw?: true
}

const FILMS: Record<string, FilmPreset> = {
  portra400: {
    r: [[0, 0.06], [0.20, 0.22], [0.5, 0.55], [0.82, 0.85], [1, 0.96]],
    g: [[0, 0.05], [0.20, 0.20], [0.5, 0.51], [0.82, 0.80], [1, 0.91]],
    b: [[0, 0.07], [0.20, 0.18], [0.5, 0.46], [0.82, 0.74], [1, 0.86]],
    saturation: 0.98, fade: 0.09,
    shadowTint: [3, 1, -1], highlightTint: [16, 4, -2], temperature: 4,
    grainStrength: 0.035, vignetteStrength: 0.12,
  },
  fuji400h: {
    r: [[0, 0.10], [0.25, 0.26], [0.5, 0.50], [0.78, 0.78], [1, 0.90]],
    g: [[0, 0.06], [0.25, 0.22], [0.5, 0.50], [0.78, 0.82], [1, 0.96]],
    b: [[0, 0.15], [0.25, 0.34], [0.5, 0.57], [0.78, 0.83], [1, 0.95]],
    saturation: 0.82, fade: 0.18,
    shadowTint: [6, -3, 9], highlightTint: [-3, 2, 6], temperature: -5,
    grainStrength: 0.028, vignetteStrength: 0.08,
  },
  cinestill: {
    r: [[0, 0.04], [0.2, 0.20], [0.5, 0.50], [0.8, 0.84], [1, 0.97]],
    g: [[0, 0.05], [0.2, 0.20], [0.5, 0.50], [0.8, 0.78], [1, 0.92]],
    b: [[0, 0.18], [0.2, 0.36], [0.5, 0.58], [0.8, 0.74], [1, 0.84]],
    saturation: 1.04, fade: 0.16,
    shadowTint: [-14, -8, 22], highlightTint: [12, 5, -10], temperature: -14,
    grainStrength: 0.06, vignetteStrength: 0.28,
    halation: 0.24,
  },
  ilford: {
    r: [[0, 0.06], [0.22, 0.18], [0.5, 0.52], [0.78, 0.86], [1, 0.96]],
    g: [[0, 0.06], [0.22, 0.18], [0.5, 0.52], [0.78, 0.86], [1, 0.96]],
    b: [[0, 0.06], [0.22, 0.18], [0.5, 0.52], [0.78, 0.86], [1, 0.96]],
    saturation: 0, fade: 0.10,
    shadowTint: [0, 0, 0], highlightTint: [0, 0, 0], temperature: 0,
    grainStrength: 0.09, vignetteStrength: 0.16,
    bw: true,
  },
}

const _lutCache: Record<string, [Uint8Array, Uint8Array, Uint8Array]> = {}

function getLUTs(key: string): [Uint8Array, Uint8Array, Uint8Array] | null {
  if (_lutCache[key]) return _lutCache[key]
  const f = FILMS[key]
  if (!f) return null
  const result: [Uint8Array, Uint8Array, Uint8Array] = [buildCurve(f.r), buildCurve(f.g), buildCurve(f.b)]
  _lutCache[key] = result
  return result
}

let _noiseTile: HTMLCanvasElement | null = null
function getNoiseTile(): HTMLCanvasElement {
  if (_noiseTile) return _noiseTile
  const sz = 256
  const c = document.createElement('canvas')
  c.width = c.height = sz
  const ctx = c.getContext('2d')!
  const img = ctx.createImageData(sz, sz)
  for (let i = 0; i < img.data.length; i += 4) {
    const n = (Math.random() - 0.5) * 255
    img.data[i] = img.data[i + 1] = img.data[i + 2] = 128 + n
    img.data[i + 3] = 255
  }
  ctx.putImageData(img, 0, 0)
  _noiseTile = c
  return c
}

export async function preloadFilmLUT(_preset: string): Promise<void> { /* curves are sync */ }

export async function applyFilmLUT(
  ctx: CanvasRenderingContext2D,
  width: number,
  height: number,
  preset: string,
): Promise<void> {
  if (!preset || preset === 'original') return
  const film = FILMS[preset]
  const luts = getLUTs(preset)
  if (!film || !luts) return

  const [rLUT, gLUT, bLUT] = luts
  const imageData = ctx.getImageData(0, 0, width, height)
  const d = imageData.data
  const { saturation: sat, fade, shadowTint, highlightTint, temperature: temp, bw } = film

  if (bw) {
    for (let i = 0; i < d.length; i += 4) {
      const lum = (0.299 * d[i] + 0.587 * d[i + 1] + 0.114 * d[i + 2]) | 0
      const v = rLUT[lum]
      d[i] = d[i + 1] = d[i + 2] = v
    }
  } else {
    for (let i = 0; i < d.length; i += 4) {
      let r = rLUT[d[i]], g = gLUT[d[i + 1]], b = bLUT[d[i + 2]]

      // Fade (lift blacks)
      if (fade > 0) {
        r = r + (255 - r) * fade * 0.18
        g = g + (255 - g) * fade * 0.18
        b = b + (255 - b) * fade * 0.18
      }

      // Tone-split tint
      const lum = (r * 0.299 + g * 0.587 + b * 0.114) / 255
      const shadowW = (1 - lum) * (1 - lum)
      const highW = lum * lum
      r += shadowTint[0] * shadowW + highlightTint[0] * highW
      g += shadowTint[1] * shadowW + highlightTint[1] * highW
      b += shadowTint[2] * shadowW + highlightTint[2] * highW

      // Temperature
      if (temp !== 0) {
        r += temp * 0.15
        b -= temp * 0.15
      }

      // Saturation (luminance-preserving)
      if (sat !== 1) {
        const ly = r * 0.299 + g * 0.587 + b * 0.114
        r = ly + (r - ly) * sat
        g = ly + (g - ly) * sat
        b = ly + (b - ly) * sat
      }

      d[i] = clamp(r); d[i + 1] = clamp(g); d[i + 2] = clamp(b)
    }
  }

  ctx.putImageData(imageData, 0, 0)

  // Halation (только Cinestill) — красное свечение вокруг ярких/красных областей
  if (film.halation && film.halation > 0) {
    const hal = film.halation
    const halCanvas = document.createElement('canvas')
    halCanvas.width = width; halCanvas.height = height
    const halCtx = halCanvas.getContext('2d')!
    const maskImg = ctx.getImageData(0, 0, width, height)
    const md = maskImg.data
    for (let i = 0; i < md.length; i += 4) {
      const r = md[i], g = md[i + 1], b = md[i + 2]
      const lm = (r * 0.299 + g * 0.587 + b * 0.114) / 255
      const redness = Math.min(1, Math.max(0, (r - Math.max(g, b)) / 80))
      const mask = Math.max(Math.max(0, lm - 0.55) / 0.45, redness * 0.7)
      md[i] = mask * 230; md[i + 1] = mask * 60; md[i + 2] = mask * 30; md[i + 3] = mask * 255
    }
    halCtx.putImageData(maskImg, 0, 0)
    const blurCanvas = document.createElement('canvas')
    blurCanvas.width = width; blurCanvas.height = height
    const bctx = blurCanvas.getContext('2d')!
    bctx.filter = `blur(${Math.max(width, height) * 0.018}px)`
    bctx.drawImage(halCanvas, 0, 0)
    ctx.globalCompositeOperation = 'screen'
    ctx.globalAlpha = hal
    ctx.drawImage(blurCanvas, 0, 0)
    ctx.globalAlpha = 1
    ctx.globalCompositeOperation = 'source-over'
  }

  // Grain
  if (film.grainStrength > 0) {
    const noise = getNoiseTile()
    const tSz = noise.width
    ctx.globalCompositeOperation = 'overlay'
    ctx.globalAlpha = film.grainStrength
    for (let y = 0; y < height; y += tSz) {
      for (let x = 0; x < width; x += tSz) {
        ctx.drawImage(noise, x, y)
      }
    }
    ctx.globalAlpha = 1
    ctx.globalCompositeOperation = 'source-over'
  }

  // Vignette
  if (film.vignetteStrength > 0) {
    const cx = width / 2, cy = height / 2
    const r = Math.sqrt(cx * cx + cy * cy)
    const grad = ctx.createRadialGradient(cx, cy, r * 0.35, cx, cy, r * 1.1)
    grad.addColorStop(0, 'rgba(0,0,0,0)')
    grad.addColorStop(1, `rgba(0,0,0,${film.vignetteStrength})`)
    ctx.globalCompositeOperation = 'source-over'
    ctx.fillStyle = grad
    ctx.fillRect(0, 0, width, height)
  }
}
