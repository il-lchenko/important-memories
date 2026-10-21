import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { VitePWA } from 'vite-plugin-pwa'
import fs from 'node:fs'

// HTTPS нужен для камеры на телефоне в локальной сети. VITE_HTTP=1 — обычный HTTP
// (встроенный браузер, автотесты); без сертификатов тоже стартуем по HTTP.
const httpsConfig =
  process.env.VITE_HTTP !== '1' && fs.existsSync('./dev-key.pem') && fs.existsSync('./dev-cert.pem')
    ? { key: fs.readFileSync('./dev-key.pem'), cert: fs.readFileSync('./dev-cert.pem') }
    : undefined

// Куда проксировать /api: по умолчанию фиктивный сервер dev-mock (8002); для проверки на
// настоящем бэкенде задайте VITE_API_TARGET (например, через SSH-туннель к тестовому контуру).
const API_TARGET = process.env.VITE_API_TARGET ?? 'http://127.0.0.1:8002'

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    VitePWA({
      registerType: 'autoUpdate',
      injectRegister: 'auto',
      strategies: 'generateSW',
      includeAssets: ['favicon.svg', 'icons/*.png', 'apple-touch-icon.png'],
      manifest: {
        name: 'Important Memories',
        short_name: 'Impomento',
        description: 'Одноразовая плёночная камера для событий',
        id: '/app',
        start_url: '/app',
        scope: '/',
        display: 'standalone',
        orientation: 'any',
        background_color: '#16100C',
        theme_color: '#16100C',
        lang: 'ru',
        icons: [
          { src: '/favicon.svg', sizes: 'any', type: 'image/svg+xml', purpose: 'any' },
          { src: '/icons/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/icons/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
          { src: '/icons/icon-maskable-192.png', sizes: '192x192', type: 'image/png', purpose: 'maskable' },
          { src: '/icons/icon-maskable-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        skipWaiting: true,
        clientsClaim: true,
        cleanupOutdatedCaches: true,
        navigateFallback: '/index.html',
        // Исключаем файловые скачивания из SPA-фолбэка, иначе SW отдаёт
        // index.html вместо реального файла (баг: клик на /im.apk открывал landing).
        navigateFallbackDenylist: [/\.apk$/, /^\/api\//, /^\/s3\//, /^\/a\//, /\.html$/, /^\/$/],
        // Не precache-им большие LUT (~4.6 MB) — они лениво по требованию.
        globPatterns: ['**/*.{js,css,html,svg,woff,woff2,ico}'],
        maximumFileSizeToCacheInBytes: 3 * 1024 * 1024,
        runtimeCaching: [
          {
            urlPattern: ({ url }) => url.pathname.startsWith('/luts/'),
            handler: 'CacheFirst',
            options: {
              cacheName: 'im-luts',
              expiration: { maxEntries: 10, maxAgeSeconds: 30 * 24 * 60 * 60 },
            },
          },
          {
            urlPattern: ({ url }) => url.origin === 'https://fonts.googleapis.com',
            handler: 'StaleWhileRevalidate',
            options: { cacheName: 'im-google-fonts-css' },
          },
          {
            urlPattern: ({ url }) => url.origin === 'https://fonts.gstatic.com',
            handler: 'CacheFirst',
            options: {
              cacheName: 'im-google-fonts-files',
              expiration: { maxEntries: 30, maxAgeSeconds: 365 * 24 * 60 * 60 },
            },
          },
          {
            urlPattern: ({ url, request }) => request.destination === 'image' && (url.pathname.startsWith('/s3/') || url.hostname === 's3.twcstorage.ru'),
            handler: 'StaleWhileRevalidate',
            options: {
              cacheName: 'im-album-images',
              expiration: { maxEntries: 400, maxAgeSeconds: 7 * 24 * 60 * 60 },
            },
          },
        ],
      },
      devOptions: { enabled: false },
    }),
  ],
  server: {
    host: '0.0.0.0',
    port: 5173,
    https: httpsConfig,
    proxy: {
      // Раздел организатора ходит сразу в /api/v1 (как Flutter-приложение).
      '/api/v1': {
        target: API_TARGET,
        changeOrigin: true,
      },
      '/api': {
        target: API_TARGET,
        changeOrigin: true,
        rewrite: (path) => path.replace(/^\/api/, '/api/v1'),
      },
    },
  },
})
