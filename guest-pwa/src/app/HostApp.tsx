import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { Navigate, Route, Routes } from 'react-router-dom'
import { CodeScreen, ConsentScreen, LoginScreen } from './auth/AuthScreens'
import { PlainShell, RequireHost, TabsShell } from './HostShell'
import DashboardScreen from './screens/DashboardScreen'
import { TopBar } from './ui'
import './host.css'

const queryClient = new QueryClient({
  defaultOptions: {
    queries: { retry: 1, refetchOnWindowFocus: true, staleTime: 15_000 },
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
            <Route path="memories" element={<ComingSoon title="Кадры" />} />
            <Route path="profile" element={<ComingSoon title="Профиль" />} />
          </Route>

          <Route element={<RequireHost><PlainShell /></RequireHost>}>
            <Route path="events/new" element={<ComingSoon title="Новый альбом" />} />
            <Route path="events/:id" element={<ComingSoon title="Событие" />} />
            <Route path="events/:id/*" element={<ComingSoon title="Событие" />} />
          </Route>

          <Route path="*" element={<Navigate to="/app" replace />} />
        </Routes>
      </div>
    </QueryClientProvider>
  )
}
