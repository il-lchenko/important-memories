/// <reference lib="webworker" />

// Пиксельная часть film-LUT: curves + fade + tone-split tint + temperature + saturation.
// Halation/grain/vignette остаются в filmLut.ts (сейчас они выключены у всех пресетов).
// Держим FILMS в синхроне с filmLut.ts.

type CurvePoints = [number, number][]

interface FilmPreset {
  r: CurvePoints
  g: CurvePoints
  b: CurvePoints
  saturation: number
  fade: number
  shadowTint: [number, number, number]
  highlightTint: [number, number, number]
  temperature: number
  bw?: true
}

const FILMS: Record<string, FilmPreset> = {
  portra400: {
    r: [[0, 0.05], [0.20, 0.22], [0.5, 0.55], [0.82, 0.86], [1, 0.98]],
    g: [[0, 0.04], [0.20, 0.20], [0.5, 0.51], [0.82, 0.83], [1, 0.95]],
    b: [[0, 0.05], [0.20, 0.19], [0.5, 0.48], [0.82, 0.82], [1, 0.93]],
    saturation: 1.0, fade: 0.06,
    shadowTint: [2, 1, -1], highlightTint: [8, 2, -1], temperature: 2,
  },
  fuji400h: {
    r: [[0, 0.08], [0.25, 0.26], [0.5, 0.50], [0.78, 0.80], [1, 0.93]],
    g: [[0, 0.05], [0.25, 0.23], [0.5, 0.51], [0.78, 0.83], [1, 0.97]],
    b: [[0, 0.11], [0.25, 0.32], [0.5, 0.56], [0.78, 0.84], [1, 0.96]],
    saturation: 0.90, fade: 0.11,
    shadowTint: [3, -1, 5], highlightTint: [-2, 1, 3], temperature: -3,
  },
  cinestill: {
    r: [[0, 0.04], [0.2, 0.20], [0.5, 0.50], [0.8, 0.86], [1, 0.98]],
    g: [[0, 0.05], [0.2, 0.22], [0.5, 0.51], [0.8, 0.82], [1, 0.95]],
    b: [[0, 0.14], [0.2, 0.32], [0.5, 0.57], [0.8, 0.78], [1, 0.90]],
    saturation: 1.02, fade: 0.11,
    shadowTint: [-8, -4, 12], highlightTint: [7, 3, -6], temperature: -8,
  },
  ilford: {
    r: [[0, 0.05], [0.22, 0.20], [0.5, 0.52], [0.78, 0.87], [1, 0.97]],
    g: [[0, 0.05], [0.22, 0.20], [0.5, 0.52], [0.78, 0.87], [1, 0.97]],
    b: [[0, 0.05], [0.22, 0.20], [0.5, 0.52], [0.78, 0.87], [1, 0.97]],
    saturation: 0, fade: 0.07,
    shadowTint: [0, 0, 0], highlightTint: [0, 0, 0], temperature: 0,
    bw: true,
  },
}

function clampByte(v: number): number {
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
    const ts = t * t * (3 - 2 * t)
    lut[i] = clampByte((y0 + (y1 - y0) * ts) * 255)
  }
  return lut
}

const _cache: Record<string, [Uint8Array, Uint8Array, Uint8Array]> = {}
function getLUTs(key: string): [Uint8Array, Uint8Array, Uint8Array] | null {
  if (_cache[key]) return _cache[key]
  const f = FILMS[key]
  if (!f) return null
  _cache[key] = [buildCurve(f.r), buildCurve(f.g), buildCurve(f.b)]
  return _cache[key]
}

interface Req {
  id: number
  preset: string
  buffer: ArrayBuffer
  width: number
  height: number
}

self.onmessage = (e: MessageEvent<Req>) => {
  const { id, preset, buffer, width, height } = e.data
  const film = FILMS[preset]
  const luts = getLUTs(preset)
  if (!film || !luts) {
    ;(self as unknown as Worker).postMessage({ id, buffer }, [buffer])
    return
  }
  const [rLUT, gLUT, bLUT] = luts
  const d = new Uint8ClampedArray(buffer)
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
      if (fade > 0) {
        r = r + (255 - r) * fade * 0.18
        g = g + (255 - g) * fade * 0.18
        b = b + (255 - b) * fade * 0.18
      }
      const lum = (r * 0.299 + g * 0.587 + b * 0.114) / 255
      const shadowW = (1 - lum) * (1 - lum)
      const highW = lum * lum
      r += shadowTint[0] * shadowW + highlightTint[0] * highW
      g += shadowTint[1] * shadowW + highlightTint[1] * highW
      b += shadowTint[2] * shadowW + highlightTint[2] * highW
      if (temp !== 0) {
        r += temp * 0.15
        b -= temp * 0.15
      }
      if (sat !== 1) {
        const ly = r * 0.299 + g * 0.587 + b * 0.114
        r = ly + (r - ly) * sat
        g = ly + (g - ly) * sat
        b = ly + (b - ly) * sat
      }
      d[i] = clampByte(r); d[i + 1] = clampByte(g); d[i + 2] = clampByte(b)
    }
  }

  ;(self as unknown as Worker).postMessage({ id, buffer: d.buffer, width, height }, [d.buffer])
}
