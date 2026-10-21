import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Navigate, Route, Routes } from 'react-router-dom'
import { CodeScreen, ConsentScreen, LoginScreen } from './auth/AuthScreens'
import { PlainShell, RequireHost, TabsShell } from './HostShell'
import CreateEventScreen from './screens/CreateEventScreen'
import DashboardScreen from './screens/DashboardScreen'
import EventRoute from './screens/EventRoute'
import HostAlbumScreen from './screens/AlbumScreen'
import { CollectionPickerScreen, CollectionScreen, CreateCollectionScreen } from './screens/CollectionScreens'
import AdminPromocodesScreen from './screens/AdminPromocodesScreen'
import CreateSoloScreen from './screens/CreateSoloScreen'
import ExtendScreen from './screens/ExtendScreen'
import InvitesScreen from './screens/InvitesScreen'
import MemoriesScreen from './screens/MemoriesScreen'
import NewScreen from './screens/NewScreen'
import PayScreen from './screens/PayScreen'
import PlusScreen from './screens/PlusScreen'
import ProfileScreen from './screens/ProfileScreen'
import ProgressScreen from './screens/ProgressScreen'
import SettingsScreen from './screens/SettingsScreen'
import PaymentReturnScreen from './screens/PaymentReturnScreen'
import QrScreen from './screens/QrScreen'
import { captureInstallPrompt } from './install'
import { stableStructuralSharing } from './stableUrls'
import { TopBar } from './ui'
import './host.css'

captureInstallPrompt()

// Установленное приложение организатора открывается сразу на разделе /app, а не на странице входа для гостей.
document.querySelector<HTMLLinkElement>('link[rel="manifest"]')?.setAttribute('href', '/host-manifest.json')

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, refetchOnWindowFocus: true, staleTime: 15_000, structuralSharing: stableStructuralSharing },
  },
})

function ComingSoon({ title }: { title: string }) {
  return (
    <>
      <TopBar title={title} back />
      <main className="host-main">
        <div className="host-card" style={{ padding: 24, marginTop: 16 }}>
          <p className="host-muted">
            Этот раздел веб-версии скоро появится. Пока он доступен в приложении для Android.
          </p>
          <a className="btn-ghost btn-sm" href="/ImpoMento.apk" style={{ marginTop: 16, maxWidth: 260 }}>
            Скачать приложение
          </a>
        </div>
      </main>
    </>
  )
}

export default function HostApp() {
  return (
    <QueryClientProvider client={queryClient}>
      <div className="host-root">
        <Routes>
          <Route path="login" element={<LoginScreen />} />
          <Route path="login/code" element={<CodeScreen />} />
          <Route path="consent" element={<ConsentScreen />} />

          <Route element={<RequireHost><TabsShell /></RequireHost>}>
            <Route index element={<DashboardScreen />} />
            <Route path="memories" element={<MemoriesScreen />} />
            <Route path="profile" element={<ProfileScreen />} />
          </Route>

          <Route element={<RequireHost><PlainShell /></RequireHost>}>
            <Route path="new" element={<NewScreen />} />
            <Route path="solo/new" element={<CreateSoloScreen />} />
            <Route path="plus" element={<PlusScreen />} />
            <Route path="admin/promocodes" element={<AdminPromocodesScreen />} />
            <Route path="collections/new" element={<CreateCollectionScreen />} />
            <Route path="collections/:id" element={<CollectionScreen />} />
            <Route path="collections/:id/add" element={<CollectionPickerScreen />} />
            <Route path="events/new" element={<CreateEventScreen />} />
            <Route path="events/:id" element={<EventRoute />} />
            <Route path="events/:id/pay" element={<PayScreen />} />
            <Route path="events/:id/qr" element={<QrScreen />} />
            <Route path="events/:id/album" element={<HostAlbumScreen />} />
            <Route path="events/:id/settings" element={<SettingsScreen />} />
            <Route path="events/:id/extend" element={<ExtendScreen />} />
            <Route path="events/:id/invites" element={<InvitesScreen />} />
            <Route path="events/:id/progress" element={<ProgressScreen />} />
            <Route path="events/:id/*" element={<ComingSoon title="Событие" />} />
          </Route>

          <Route path="payment/return" element={<RequireHost><PaymentReturnScreen /></RequireHost>} />

          <Route path="*" element={<Navigate to="/app" replace />} />
        </Routes>
      </div>
    </QueryClientProvider>
  )
}
