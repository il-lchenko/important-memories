// Фиктивный API для разработки раздела организатора (/app) без настоящего сервера.
// Запуск: node dev-mock/server.mjs  (порт 8002 — туда смотрит прокси Vite /api/v1).
// Данные живут в памяти и сбрасываются при перезапуске.
import http from 'node:http'
import { randomUUID } from 'node:crypto'

const PORT = Number(process.env.MOCK_PORT ?? 8002)
const now = () => new Date().toISOString()
const day = (n) => new Date(Date.now() + n * 86400000).toISOString()

const svg = (label, hue, w = 600, h = 800) =>
  'data:image/svg+xml;utf8,' + encodeURIComponent(
    `<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="hsl(${hue},45%,62%)"/><stop offset="1" stop-color="hsl(${(hue + 40) % 360},40%,32%)"/></linearGradient></defs><rect width="100%" height="100%" fill="url(#g)"/><text x="50%" y="50%" fill="#fff" fill-opacity=".85" font-size="44" font-family="sans-serif" text-anchor="middle">${label}</text></svg>`,
  )

const settings = (over = {}) => ({
  frames_per_guest: 30, max_guests: 25, reveal_mode: 'instant', reveal_at: null, plan: 'p25',
  lut_preset: 'portra400', sound_enabled: true, photo_format: 'portrait_34', uploads_enabled: false,
  uploads_window_ends_at: null, qr_style: null, title_font: null, ...over,
})
const mkEvent = (title, status, over = {}, sOver = {}) => ({
  id: randomUUID(), short_code: Math.random().toString(36).slice(2, 10), title,
  start_at: day(-3), end_at: day(2), expires_at: day(55), event_type: 'wedding', status,
  cover_url: null, created_at: day(-4), updated_at: now(), settings: settings(sOver),
  guests_count: 12, frames_count: 84, pin_enabled: false, kind: 'event', ...over,
})

const state = {
  events: [
    mkEvent('Свадьба Ани и Пети', 'active', { cover_url: svg('Свадьба', 20, 800, 450) }),
    mkEvent('День рождения Маши', 'completed', { event_type: 'birthday', cover_url: svg('Маша', 200, 800, 450), expires_at: day(20) }, { plan: 'p10', max_guests: 10 }),
    mkEvent('Грузия, осень', 'active', { kind: 'solo', event_type: 'other', guests_count: 1, frames_count: 14, expires_at: day(25), cover_url: svg('Грузия', 140, 800, 450) }, { plan: 'free', max_guests: 1, frames_per_guest: 150, uploads_enabled: true }),
    mkEvent('Корпоратив Q4', 'draft', { event_type: 'corporate', guests_count: 0, frames_count: 0, expires_at: null }, { plan: 'free', max_guests: 5 }),
  ],
  frames: {},
  invites: {},
  pins: {},
  publicShare: {},
  codes: new Map(),
  collections: [],
  plus: false,
  soloUsed: 14,
}
state.events.forEach((e, i) => {
  state.frames[e.id] = Array.from({ length: e.status === 'draft' ? 0 : 14 }, (_, k) => ({
    id: randomUUID(), guest_id: randomUUID(), guest_name: ['Аня', 'Пётр', 'Маша', 'Олег'][k % 4],
    guest_avatar_url: null, captured_at: day(-2 + k * 0.1),
    thumbnail_url: svg(`#${k + 1}`, (k * 37 + i * 90) % 360, 300, 400),
    preview_url: svg(`#${k + 1}`, (k * 37 + i * 90) % 360, 900, 1200),
    full_url: svg(`#${k + 1}`, (k * 37 + i * 90) % 360, 1200, 1600),
    width: 3000, height: 4000, is_mine: k % 5 === 0, caption: k % 3 === 0 ? 'Лучший момент' : null,
    voice_url: null, voice_duration_ms: null, voice_peaks: null, rotation: 0, note: null, source: 'camera',
  }))
})

const json = (res, code, body) => {
  res.writeHead(code, { 'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*' })
  res.end(body === undefined ? '' : JSON.stringify(body))
}
const err = (res, code, message, errCode = 'CONFLICT') => json(res, code, { error: { code: errCode, message, details: {} } })
const readBody = (req) => new Promise((resolve) => {
  let d = ''
  req.on('data', (c) => { d += c })
  req.on('end', () => { try { resolve(d ? JSON.parse(d) : {}) } catch { resolve({}) } })
})

const PRICES = [['free', 5, 0, 30], ['p10', 10, 24900, 30], ['p25', 25, 44900, 60], ['p50', 50, 129000, 90], ['p75', 75, 199000, 90],
  ['p100', 100, 299000, 120], ['p150', 150, 449000, 150], ['p175', 175, 549000, 180], ['p200', 200, 629000, 180], ['p250', 250, 769000, 180]]
const pricing = () => ({
  currency: 'RUB',
  tiers: PRICES.map(([plan, max_guests, price_kopecks, retention_days]) => ({ plan, max_guests, price_kopecks, retention_days })),
  custom: { from_guests: 251, max_guests: 2000, base_price_kopecks: 769000, per_guest_kopecks: 3500, retention_days: 180 },
  frames: { base_per_guest: 30, extended_per_guest: 45, price_per_guest_kopecks: 1000 },
  extend: [
    { period: '3m', days: 90, price_kopecks: 49000, per_guest_kopecks: 1000 },
    { period: '6m', days: 180, price_kopecks: 79000, per_guest_kopecks: 1700 },
    { period: '1y', days: 365, price_kopecks: 129000, per_guest_kopecks: 3200 },
  ],
  solo_extend: [
    { period: '3m', days: 90, price_kopecks: 9900, per_guest_kopecks: 0 },
    { period: '6m', days: 180, price_kopecks: 17900, per_guest_kopecks: 0 },
    { period: '1y', days: 365, price_kopecks: 29900, per_guest_kopecks: 0 },
  ],
  plus: { enabled: true, month_kopecks: 22900, year_kopecks: 219000, solo_frames_per_month: 500, solo_free_frames_per_month: 150, solo_retention_days: 3650, solo_free_retention_days: 90, events_active: 3, events_per_month: 6, free_events_active: 2, free_events_per_month: 4, mini_frames_per_album: 100, mini_free_albums: 3, mini_free_frames_per_album: 30 },
  upgrade_premium: 1.15, free_active_events: 2, free_events_per_month: 4,
})

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x')
  const path = url.pathname.replace(/^\/api\/v1/, '')
  const m = req.method
  if (m === 'OPTIONS') {
    res.writeHead(204, { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': '*' })
    return res.end()
  }
  const body = ['POST', 'PATCH', 'PUT', 'DELETE'].includes(m) ? await readBody(req) : {}
  console.log(m, path)

  if (path === '/auth/email/request' && m === 'POST') return json(res, 200, { ok: true, cooldown_seconds: 60 })
  if (path === '/auth/email/verify' && m === 'POST') {
    if (body.code !== '111111') return err(res, 400, 'Неверный код', 'BAD_CODE')
    return json(res, 200, { access_token: 'mock-access', refresh_token: 'mock-refresh', token_type: 'bearer' })
  }
  if (path === '/auth/refresh') return json(res, 200, { access_token: 'mock-access', refresh_token: 'mock-refresh', token_type: 'bearer' })
  if (path === '/consent/status') return json(res, 200, { current_version: '2.4', needs_accept: false, missing: [] })
  if (path === '/consent' && m === 'POST') return json(res, 200, {})
  if (path === '/users/me') {
    if (m === 'PATCH') return json(res, 200, { email: 'host@example.com', display_name: body.display_name ?? 'Илья', avatar_url: null, is_admin: false, referral_code: 'IM-ABC234' })
    if (m === 'DELETE') return json(res, 204)
    return json(res, 200, { email: 'host@example.com', display_name: 'Илья', avatar_url: null, is_admin: false, referral_code: 'IM-ABC234' })
  }
  if (path === '/pricing') return json(res, 200, pricing())
  if (path === '/me/entitlements') {
    return json(res, 200, { tier: 'free', is_admin: false, subscription_enabled: false, free_events_per_month: 4, free_events_used: 1,
      free_events_left: 3, free_active_limit: 2, free_active_used: 1, free_active_left: 1,
      plus: state.plus, solo_frames_per_month: state.plus ? 500 : 150, solo_frames_used: state.soloUsed, solo_frames_left: (state.plus ? 500 : 150) - state.soloUsed,
      solo_stored_limit: 300, solo_stored_used: state.soloUsed, solo_retention_days: state.plus ? 3650 : 90,
      mini_albums_limit: state.plus ? null : 3, mini_frames_per_album: state.plus ? 100 : 30,
      features: { solo_album: true, mini_albums: true, extra_styles: state.plus } })
  }
  if (path === '/me/referrals') return json(res, 200, { referral_code: 'IM-ABC234', referrals_count: 2, total_earned_kopecks: 0, pending_promocodes_count: 1 })
  if (path === '/me/promocodes') return json(res, 200, [])
  if (path === '/promocodes/validate') {
    if ((body.code ?? '').toUpperCase() === 'TEST20') return json(res, 200, { valid: true, discount_kopecks: 9000, final_amount_kopecks: 35900, original_amount_kopecks: 44900 })
    return json(res, 200, { valid: false, discount_kopecks: 0, error: 'Промокод не найден' })
  }
  if (path === '/memories/') {
    return json(res, 200, { blocks: state.events.filter((e) => e.status !== 'draft').map((e) => ({
      type: 'grid_6', kind: 'single', title: e.title, date_iso: e.start_at, albums_count: 1, event_id: e.id, event_ids: [e.id],
      event_type: e.event_type, thumbs: state.frames[e.id].slice(0, 6).map((f) => ({ url: f.thumbnail_url, event_id: e.id, frame_id: f.id, rotation: 0 })),
    })) })
  }
  if (path === '/events/solo' && m === 'POST') {
    const e = mkEvent(body.title ?? 'Соло', 'active', { kind: 'solo', event_type: 'other', guests_count: 1, frames_count: 0, expires_at: day(30) },
      { plan: 'free', max_guests: 1, frames_per_guest: 150, uploads_enabled: true, lut_preset: body.lut_preset ?? 'portra400' })
    state.events.unshift(e); state.frames[e.id] = []
    return json(res, 201, e)
  }
  const subInfo = () => ({ enabled: true, plus: state.plus, status: state.plus ? 'active' : null, period: state.plus ? 'month' : null,
    current_period_end: state.plus ? day(30) : null, cancel_at_period_end: !!state.cancelPlus, month_kopecks: 22900, year_kopecks: 219000 })
  if (path === '/me/subscription') return json(res, 200, subInfo())
  if (path === '/subscription/checkout' && m === 'POST') { state.plus = true; return json(res, 200, { payment_id: randomUUID(), confirmation_url: 'http://localhost:5174/payment/return?kind=subscription', amount_kopecks: 22900, currency: 'RUB' }) }
  if (path === '/subscription/cancel' && m === 'POST') { state.cancelPlus = true; return json(res, 200, subInfo()) }
  if (path === '/subscription/resume' && m === 'POST') { state.cancelPlus = false; return json(res, 200, subInfo()) }

  const colView = (c) => {
    const items = c.items.map((fid) => { for (const [eid, list] of Object.entries(state.frames)) { const f = list.find((x) => x.id === fid); if (f) return { f, eid } } return null }).filter(Boolean)
    return {
      id: c.id, title: c.title, created_at: c.created_at, frames_limit: state.plus ? 100 : 30, unavailable_count: c.items.length - items.length,
      items: items.map(({ f, eid }) => ({ id: f.id, event_id: eid, event_title: state.events.find((e) => e.id === eid)?.title ?? '', captured_at: f.captured_at,
        thumbnail_url: f.thumbnail_url, preview_url: f.preview_url, full_url: f.full_url, width: f.width, height: f.height, rotation: f.rotation, caption: f.caption, is_mine: f.is_mine })),
    }
  }
  if (path === '/collections/') {
    if (m === 'POST') {
      if (!state.plus && state.collections.length >= 3) return err(res, 409, 'Можно создать 3 мини-альбома бесплатно.')
      const c = { id: randomUUID(), title: body.title, created_at: now(), items: [] }
      state.collections.unshift(c); return json(res, 201, colView(c))
    }
    return json(res, 200, { albums_limit: state.plus ? null : 3, frames_per_album: state.plus ? 100 : 30, collections: state.collections.map((c) => {
      const v = colView(c); return { id: c.id, title: c.title, items_count: v.items.length, created_at: c.created_at, preview_urls: v.items.slice(0, 4).map((i) => i.thumbnail_url) }
    }) })
  }
  const cm = path.match(/^\/collections\/([^/]+)(\/items(?:\/([^/]+))?)?$/)
  if (cm) {
    const c = state.collections.find((x) => x.id === cm[1])
    if (!c) return err(res, 404, 'Collection not found', 'NOT_FOUND')
    if (!cm[2]) {
      if (m === 'PATCH') { c.title = body.title; return json(res, 204) }
      if (m === 'DELETE') { state.collections = state.collections.filter((x) => x.id !== c.id); return json(res, 204) }
      return json(res, 200, colView(c))
    }
    if (cm[3] && m === 'DELETE') { c.items = c.items.filter((i) => i !== cm[3]); return json(res, 204) }
    if (m === 'POST') { for (const fid of body.frame_ids ?? []) if (!c.items.includes(fid)) c.items.push(fid); return json(res, 200, colView(c)) }
  }
  if (path === '/events/invited') return json(res, 200, [])
  if (path === '/events/') {
    if (m === 'POST') {
      const title = body.title ?? body.name ?? 'Событие'
      const plan = body.plan ?? 'free'
      const tier = PRICES.find((p) => p[0] === plan) ?? PRICES[0]
      const e = mkEvent(title, 'draft', { event_type: body.event_type ?? 'other', guests_count: 0, frames_count: 0, expires_at: null },
        { plan, max_guests: tier[1], frames_per_guest: body.frames_per_guest ?? 30, lut_preset: body.lut_preset ?? body.film ?? 'portra400',
          uploads_enabled: !!body.uploads_enabled, reveal_mode: body.reveal_mode ?? 'instant', reveal_at: body.reveal_at ?? null })
      state.events.unshift(e); state.frames[e.id] = []
      return json(res, 201, e)
    }
    return json(res, 200, state.events)
  }

  const em = path.match(/^\/events\/([^/]+)(\/.*)?$/)
  if (em) {
    const ev = state.events.find((e) => e.id === em[1])
    const sub = em[2] ?? ''
    if (!ev) return err(res, 404, 'Event not found', 'NOT_FOUND')
    if (sub === '') {
      if (m === 'PATCH') { Object.assign(ev, body); ev.updated_at = now(); return json(res, 200, ev) }
      if (m === 'DELETE') { if (ev.status === 'active' && ev.kind !== 'solo') return err(res, 409, 'Нельзя удалить активное событие'); ev.status = 'cancelled'; return json(res, 204) }
      return json(res, 200, ev)
    }
    if (sub === '/settings' && m === 'PATCH') { Object.assign(ev.settings, body); return json(res, 200, ev) }
    if (sub === '/activate') { ev.status = 'active'; ev.expires_at = day(30); return json(res, 200, ev) }
    if (sub === '/complete' || sub === '/reveal') { ev.status = 'completed'; return json(res, 200, ev) }
    if (sub === '/checkout') {
      const tier = PRICES.find((p) => p[0] === body.plan) ?? PRICES[1]
      ev.settings.plan = tier[0]; ev.settings.max_guests = tier[1]; ev.status = 'active'; ev.expires_at = day(tier[3])
      return json(res, 200, { payment_id: randomUUID(), yookassa_id: '', confirmation_url: '', amount_kopecks: tier[2], currency: 'RUB', discount_kopecks: 0, admin_bypass: true })
    }
    if (sub === '/extend') { ev.expires_at = day(120); return json(res, 200, { payment_id: randomUUID(), yookassa_id: '', confirmation_url: '', amount_kopecks: 49000, admin_bypass: true, period: body.period, days_added: 90, new_expires_at: ev.expires_at, discount_kopecks: 0 }) }
    if (sub === '/upgrade') {
      if (body.kind === 'frames') ev.settings.frames_per_guest = 45
      else ev.settings.max_guests = Math.min(250, ev.settings.max_guests * 2)
      return json(res, 200, { payment_id: randomUUID(), yookassa_id: '', confirmation_url: '', amount_kopecks: 10000, admin_bypass: true, kind: body.kind, discount_kopecks: 0 })
    }
    if (sub === '/pin') {
      const pin = state.pins[ev.id] ?? { pin_enabled: false, entry_pin: null }
      if (m === 'PATCH') { state.pins[ev.id] = { pin_enabled: !!body.enabled, entry_pin: body.enabled ? (body.pin ?? String(1000 + Math.floor(Math.random() * 9000))) : null }; return json(res, 200, state.pins[ev.id]) }
      return json(res, 200, pin)
    }
    if (sub === '/join-stats') return json(res, 200, { window_hours: 24, total: 18, ok: 15, bad_code: 1, bad_pin: 1, pin_required: 1, rate_limited: 0, other: 0, unique_ips: 9, unique_fingerprints: 12, suspicious: false })
    if (sub === '/invites') {
      state.invites[ev.id] ??= []
      if (m === 'POST') {
        const t = randomUUID().replace(/-/g, '').slice(0, 20)
        const inv = { id: randomUUID(), token: t, display_name: body.display_name, created_at: now(), used_at: null, expires_at: body.ttl_days ? day(body.ttl_days) : null, invite_url: `http://localhost:5174/i/${t}` }
        state.invites[ev.id].unshift(inv); return json(res, 201, inv)
      }
      return json(res, 200, state.invites[ev.id])
    }
    const im = sub.match(/^\/invites\/([^/]+)$/)
    if (im && m === 'DELETE') { state.invites[ev.id] = (state.invites[ev.id] ?? []).filter((i) => i.id !== im[1]); return json(res, 204) }
    if (sub === '/public-share') {
      if (m === 'DELETE') { state.publicShare[ev.id] = null; return json(res, 204) }
      return json(res, 200, { public_share_token: state.publicShare[ev.id] ?? null })
    }
    if (sub === '/public-share/enable' || sub === '/public-share/regenerate') { state.publicShare[ev.id] = randomUUID().replace(/-/g, ''); return json(res, 200, { public_share_token: state.publicShare[ev.id] }) }
    if (sub === '/uploads-window') { ev.settings.uploads_window_ends_at = m === 'DELETE' ? null : day(1); return json(res, m === 'DELETE' ? 204 : 200, { uploads_window_ends_at: ev.settings.uploads_window_ends_at }) }
    if (sub === '/download' && m === 'POST') return json(res, 202, { job_id: 'job1', status: 'pending' })
    if (sub.startsWith('/download/')) return json(res, 200, { job_id: 'job1', status: 'ready', download_url: 'http://localhost/archive.zip', frame_count: state.frames[ev.id].length })
    if (sub === '/cover' && m === 'POST') { ev.cover_url = svg('Новая обложка', 120, 800, 450); return json(res, 200, ev) }
    if (sub === '/album') {
      const items = state.frames[ev.id].filter((f) => !f.deleted)
      return json(res, 200, { items, next_cursor: null, revealed: true, total_frames: items.length, is_admin_preview: false, title_font: ev.settings.title_font })
    }
    const fm = sub.match(/^\/frames\/([^/]+)(\/rotation)?$/)
    if (fm) {
      const f = state.frames[ev.id].find((x) => x.id === fm[1])
      if (!f) return err(res, 404, 'Frame not found', 'NOT_FOUND')
      if (fm[2] && m === 'PATCH') { f.rotation = body.rotation; return json(res, 200, f) }
      if (m === 'DELETE') { f.deleted = true; return json(res, 204) }
    }
  }
  return err(res, 404, `mock: ${m} ${path} не реализован`, 'NOT_FOUND')
})

server.listen(PORT, () => console.log(`mock api on :${PORT}`))
