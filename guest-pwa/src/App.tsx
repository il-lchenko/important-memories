import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import HomeScreen from './features/home/HomeScreen'
import LandingScreen from './features/landing/LandingScreen'
import CameraScreen from './features/camera/CameraScreen'
import AlbumScreen from './features/album/AlbumScreen'
import FrameFullscreen from './features/album/FrameFullscreen'
import DoneScreen from './features/shared/DoneScreen'
import WaitingScreen from './features/shared/WaitingScreen'
import EventEndedScreen from './features/shared/EventEndedScreen'
import NotStartedScreen from './features/shared/NotStartedScreen'
import SignChoiceScreen from './features/sign/SignChoiceScreen'
import CaptionScreen from './features/sign/CaptionScreen'
import VoiceScreen from './features/sign/VoiceScreen'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/"                                      element={<HomeScreen />} />
        <Route path="/g/:shortCode"                          element={<LandingScreen />} />
        <Route path="/g/:shortCode/camera"                   element={<CameraScreen />} />
        <Route path="/g/:shortCode/album"                    element={<AlbumScreen />} />
        <Route path="/g/:shortCode/f/:frameIndex"            element={<FrameFullscreen />} />
        <Route path="/g/:shortCode/sign/:frameId"            element={<SignChoiceScreen />} />
        <Route path="/g/:shortCode/sign/:frameId/text"       element={<CaptionScreen />} />
        <Route path="/g/:shortCode/sign/:frameId/voice"      element={<VoiceScreen />} />
        <Route path="/g/:shortCode/done"                     element={<DoneScreen />} />
        <Route path="/g/:shortCode/waiting"                  element={<WaitingScreen />} />
        <Route path="/g/:shortCode/ended"                    element={<EventEndedScreen />} />
        <Route path="/g/:shortCode/not-started"              element={<NotStartedScreen />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
