import axios from 'axios'

const BASE = import.meta.env.VITE_API_URL ?? '/api'

export const api = axios.create({
  baseURL: BASE,
  headers: { 'Content-Type': 'application/json' },
  timeout: 30_000,
})

// Guest token goes in X-Guest-Token (not Authorization Bearer)
api.interceptors.request.use((config) => {
  const token = sessionStorage.getItem('guest_token')
  if (token) config.headers['X-Guest-Token'] = token
  return config
})

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
  frames_used: number
  frames_remaining: number
  event: {
    id: string
    title: string
    status: string
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
}
