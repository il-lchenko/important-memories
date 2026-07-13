import axios from 'axios'

const BASE = import.meta.env.VITE_API_URL ?? '/api'

export const api = axios.create({
  baseURL: BASE,
  headers: { 'Content-Type': 'application/json' },
  timeout: 60_000,
})

export class UploadError extends Error {
  readonly stage: 'presign' | 's3_put' | 'register'
  readonly status?: number
  readonly retryable: boolean
  constructor(stage: 'presign' | 's3_put' | 'register', message: string, opts: { status?: number; retryable?: boolean } = {}) {
    super(message)
    this.name = 'UploadError'
    this.stage = stage
    this.status = opts.status
    this.retryable = opts.retryable ?? true
  }
}

export async function uploadPutBlob(url: string, blob: Blob, signal: AbortSignal): Promise<void> {
  let res: Response
  try {
    res = await fetch(url, {
      method: 'PUT',
      body: blob,
      headers: { 'Content-Type': blob.type || 'image/jpeg' },
      signal,
      cache: 'no-store',
      credentials: 'omit',
      mode: 'cors',
    })
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'network error'
    throw new UploadError('s3_put', `network: ${msg}`, { retryable: true })
  }
  if (!res.ok) {
    // 4xx (кроме 408/429) — presigned URL истёк, надо запросить новый (retryable=true, но выше слой попросит новый presign)
    throw new UploadError('s3_put', `s3 ${res.status}`, { status: res.status, retryable: true })
  }
}

// Guest token goes in X-Guest-Token (not Authorization Bearer)
api.interceptors.request.use((config) => {
  const token = sessionStorage.getItem('guest_token')
  if (token) config.headers['X-Guest-Token'] = token
  return config
})

// On 401 — guest token is missing or invalid. Drop everything and bounce to landing.
api.interceptors.response.use(
  (r) => r,
  (err) => {
    if (err?.response?.status === 401) {
      const path = window.location.pathname
      const match = path.match(/^\/g\/([^/]+)/)
      const shortCode = match?.[1]
      // Already on landing — don't loop
      if (shortCode && path !== `/g/${shortCode}`) {
        sessionStorage.removeItem('guest_token')
        sessionStorage.removeItem('guest_id')
        sessionStorage.removeItem('guest_name')
        sessionStorage.removeItem('event')
        // Don't touch localStorage `gt_*` — LandingScreen will restore from it if still valid
        window.location.replace(`/g/${shortCode}`)
      }
    }
    return Promise.reject(err)
  },
)

function generateFingerprint(): string {
  const raw = [
    navigator.userAgent,
    String(screen.width),
    String(screen.height),
    navigator.language,
    String(new Date().getTimezoneOffset()),
  ].join(':')
  let hash = 5381
  for (let i = 0; i < raw.length; i++) {
    hash = ((hash << 5) + hash) + raw.charCodeAt(i)
    hash >>>= 0
  }
  return hash.toString(16).padStart(8, '0')
}

export interface GuestEventSettings {
  frames_per_guest: number
  max_guests: number
  reveal_mode: string
  reveal_at: string | null
  plan: string
  lut_preset: string
  sound_enabled: boolean
}

export interface GuestSessionResponse {
  guest_token: string
  guest_id: string
  name?: string
  avatar_url?: string | null
  bio?: string | null
  frames_used: number
  frames_remaining: number
  event: {
    id: string
    title: string
    status: string
    start_at: string | null
    end_at: string
    settings: GuestEventSettings
  }
}

export interface PresignResponse {
  frame_id: string
  upload_url: string
  expires_in: number
}

export interface RegisterFrameResponse {
  id: string
  status: string
  frames_remaining: number
}

export interface VoicePresignResponse {
  voice_s3_key: string
  upload_url: string
  expires_in: number
}

export interface FrameUpdatePayload {
  caption?: string | null
  voice_s3_key?: string | null
  voice_duration_ms?: number | null
  voice_peaks?: number[] | null
  clear_caption?: boolean
  clear_voice?: boolean
}

export interface PublicAlbumMeta {
  id: string
  title: string
  status: string
  cover_url: string | null
  total_frames: number
  revealed: boolean
}

export const publicApi = {
  getAlbumMeta(token: string) {
    return api.get<PublicAlbumMeta>(`/public/albums/${token}`)
  },
  listFrames(token: string, cursor?: string | null, limit = 30) {
    const params: Record<string, string | number> = { limit }
    if (cursor) params.cursor = cursor
    return api.get(`/public/albums/${token}/frames`, { params })
  },
}

export const hostApi = {
  getPublicShare(eventId: string) {
    return api.get<{ public_share_token: string }>(`/events/${eventId}/public-share`)
  },
  regeneratePublicShare(eventId: string) {
    return api.post<{ public_share_token: string }>(`/events/${eventId}/public-share/regenerate`)
  },
}

export interface AvatarPresignResponse {
  avatar_key: string
  upload_url: string
  expires_in: number
}

export interface GuestProfileUpdatePayload {
  name?: string
  avatar_key?: string
  bio?: string | null
}

export const guestApi = {
  createSession(shortCode: string, guestName: string) {
    return api.post<GuestSessionResponse>('/guest/sessions', {
      short_code: shortCode,
      name: guestName,
      fingerprint: generateFingerprint(),
    })
  },
  getSession() {
    return api.get<GuestSessionResponse>('/guest/sessions/me')
  },
  updateProfile(payload: GuestProfileUpdatePayload) {
    return api.patch<GuestSessionResponse & { avatar_url?: string | null; bio?: string | null }>(
      '/guest/profile',
      payload,
    )
  },
  updateName(name: string) {
    return api.patch<GuestSessionResponse>('/guest/sessions/me', { name })
  },
  avatarPresign(sizeBytes: number, contentType = 'image/jpeg') {
    return api.post<AvatarPresignResponse>('/guest/avatar/presign', {
      content_type: contentType,
      size_bytes: sizeBytes,
    })
  },
  presign(sizeBytes: number, mimeType = 'image/jpeg') {
    return api.post<PresignResponse>('/guest/frames/presign', {
      content_type: mimeType,
      size_bytes: sizeBytes,
    })
  },
  registerFrame(frameId: string, capturedAt: string, width: number, height: number) {
    return api.post<RegisterFrameResponse>('/guest/frames/', {
      frame_id: frameId,
      captured_at: capturedAt,
      width,
      height,
    })
  },
  voicePresign(frameId: string, sizeBytes: number, contentType = 'audio/webm') {
    return api.post<VoicePresignResponse>(`/guest/frames/${frameId}/voice-presign`, {
      size_bytes: sizeBytes,
      content_type: contentType,
    })
  },
  updateFrame(frameId: string, payload: FrameUpdatePayload) {
    return api.patch<void>(`/guest/frames/${frameId}`, payload)
  },
}
