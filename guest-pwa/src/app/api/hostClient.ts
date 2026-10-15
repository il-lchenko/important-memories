import axios, { AxiosError, type InternalAxiosRequestConfig } from 'axios'
import type { components } from '../../api/schema'

export type Schemas = components['schemas']
export type EventOut = Schemas['EventOut']
export type InvitedEventOut = Schemas['InvitedEventOut']
export type UserOut = Schemas['UserOut']
export type TokenOut = Schemas['TokenOut']

const ACCESS_KEY = 'im_host_access'
const REFRESH_KEY = 'im_host_refresh'

function read(key: string): string | null {
  try { return localStorage.getItem(key) } catch { return null }
}

export const hostTokens = {
  get access(): string | null { return read(ACCESS_KEY) },
  get refresh(): string | null { return read(REFRESH_KEY) },
  save(tokens: { access_token: string; refresh_token: string }) {
    try {
      localStorage.setItem(ACCESS_KEY, tokens.access_token)
      localStorage.setItem(REFRESH_KEY, tokens.refresh_token)
    } catch { /* приватный режим — останемся в сессии без сохранения */ }
  },
  clear() {
    try {
      localStorage.removeItem(ACCESS_KEY)
      localStorage.removeItem(REFRESH_KEY)
    } catch { /* ignore */ }
  },
  isLoggedIn(): boolean { return !!read(ACCESS_KEY) },
}

const BASE_URL = import.meta.env.VITE_HOST_API_URL ?? '/api/v1'

export const hostApi = axios.create({ baseURL: BASE_URL, timeout: 60_000 })

hostApi.interceptors.request.use((config) => {
  const token = hostTokens.access
  if (token) config.headers.Authorization = `Bearer ${token}`
  return config
})

let refreshing: Promise<string | null> | null = null

async function refreshAccess(): Promise<string | null> {
  const refreshToken = hostTokens.refresh
  if (!refreshToken) return null
  try {
    const { data } = await axios.post<TokenOut>(`${BASE_URL}/auth/refresh`, { refresh_token: refreshToken })
    hostTokens.save(data)
    return data.access_token
  } catch {
    return null
  }
}

export function goToLogin() {
  hostTokens.clear()
  const back = window.location.pathname + window.location.search
  window.location.replace(`/app/login?next=${encodeURIComponent(back)}`)
}

hostApi.interceptors.response.use(
  (r) => r,
  async (error: AxiosError) => {
    const original = error.config as (InternalAxiosRequestConfig & { _retried?: boolean }) | undefined
    const isAuthCall = original?.url?.startsWith('/auth/') ?? false
    if (error.response?.status === 401 && original && !original._retried && !isAuthCall) {
      original._retried = true
      refreshing ??= refreshAccess().finally(() => { refreshing = null })
      const token = await refreshing
      if (token) {
        original.headers.Authorization = `Bearer ${token}`
        return hostApi(original)
      }
      goToLogin()
    }
    return Promise.reject(error)
  },
)

/** Человеческое сообщение из ошибки API ({error:{message}} или FastAPI {detail}). */
export function apiErrorMessage(e: unknown, fallback = 'Что-то пошло не так. Попробуйте ещё раз.'): string {
  if (axios.isAxiosError(e)) {
    if (!e.response) return 'Нет соединения с сервером'
    if (e.response.status >= 500) return 'Сервер временно недоступен. Попробуйте чуть позже.'
    const data = e.response.data as { error?: { message?: string; code?: string }; detail?: unknown } | undefined
    if (data?.error?.code === 'RATE_LIMITED') return 'Слишком много попыток. Подождите немного.'
    if (data?.error?.message) return data.error.message
    if (typeof data?.detail === 'string') return data.detail
  }
  return fallback
}

export function newIdempotencyKey(): string {
  if (typeof crypto !== 'undefined' && 'randomUUID' in crypto) return crypto.randomUUID()
  return `${Date.now()}-${Math.random().toString(16).slice(2)}`
}

export function deviceFingerprint(): string {
  try {
    let fp = localStorage.getItem('im_fp_v2')
    if (!fp) {
      const bytes = new Uint8Array(16)
      crypto.getRandomValues(bytes)
      fp = Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')
      localStorage.setItem('im_fp_v2', fp)
    }
    return fp
  } catch {
    return '00000000'
  }
}
