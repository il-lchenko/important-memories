import { useEffect } from 'react'
import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import HomeScreen from './features/home/HomeScreen'
import LandingScreen from './features/landing/LandingScreen'
import CameraScreen from './features/camera/CameraScreen'
import AlbumScreen from './features/album/AlbumScreen'
import PublicAlbumScreen from './features/album/PublicAlbumScreen'
import FrameFullscreen from './features/album/FrameFullscreen'
import DoneScreen from './features/shared/DoneScreen'
import WaitingScreen from './features/shared/WaitingScreen'
import EventEndedScreen from './features/shared/EventEndedScreen'
import NotStartedScreen from './features/shared/NotStartedScreen'
import SignChoiceScreen from './features/sign/SignChoiceScreen'
import CaptionScreen from './features/sign/CaptionScreen'
import VoiceScreen from './features/sign/VoiceScreen'
import ProfileScreen from './features/profile/ProfileScreen'
import InvitePage from './features/invite/InvitePage'
import DevAlbumPreview from './features/album/DevAlbumPreview'

export default function App() {
  useEffect(() => {
    // Ловим ?ref=IM-XXXXXX на любой странице landing/PWA и сохраняем
    // в localStorage — при переходе в host-app он подхватит из web-storage
    // (через query param в install prompt / share intent).
    const params = new URLSearchParams(window.location.search)
    const ref = params.get('ref')
    if (ref && /^IM-[A-Z0-9]{6}$/i.test(ref)) {
      const normalized = ref.trim().toUpperCase()
      localStorage.setItem('pending_ref_code', normalized)
      // Прокидываем на страницу /get-app для host-app deep link.
      // Убираем ?ref из адресной строки, чтобы не логировать при аналитике.
      const url = new URL(window.location.href)
      url.searchParams.delete('ref')
      window.history.replaceState({}, '', url.toString())
    }
  }, [])

  return (
    <BrowserRouter>
      <Routes>
        <Route path="/"                                      element={<HomeScreen />} />
        <Route path="/join"                                  element={<HomeScreen />} />
        <Route path="/g/:shortCode"                          element={<LandingScreen />} />
        <Route path="/g/:shortCode/camera"                   element={<CameraScreen />} />
        <Route path="/g/:shortCode/album"                    element={<AlbumScreen />} />
        <Route path="/g/:shortCode/f/:frameIndex"            element={<FrameFullscreen />} />
        <Route path="/g/:shortCode/sign/:frameId"            element={<SignChoiceScreen />} />
        <Route path="/g/:shortCode/sign/:frameId/text"       element={<CaptionScreen />} />
        <Route path="/g/:shortCode/sign/:frameId/voice"      element={<VoiceScreen />} />
        <Route path="/g/:shortCode/profile"                  element={<ProfileScreen />} />
        <Route path="/g/:shortCode/done"                     element={<DoneScreen />} />
        <Route path="/g/:shortCode/waiting"                  element={<WaitingScreen />} />
        <Route path="/g/:shortCode/ended"                    element={<EventEndedScreen />} />
        <Route path="/g/:shortCode/not-started"              element={<NotStartedScreen />} />
        <Route path="/a/:token"                              element={<PublicAlbumScreen />} />
        <Route path="/a/:token/f/:frameIndex"                element={<FrameFullscreen />} />
        <Route path="/i/:token"                              element={<InvitePage />} />
        {import.meta.env.DEV && (
          <Route path="/dev/album-preview"                   element={<DevAlbumPreview />} />
        )}
        <Route path="*" element={<Navigate to="/join" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
