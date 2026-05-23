import { BrowserRouter, Routes, Route, Navigate } from 'react-router-dom'
import LandingScreen from './features/landing/LandingScreen'
import CameraScreen from './features/camera/CameraScreen'
import AlbumScreen from './features/album/AlbumScreen'
import FrameFullscreen from './features/album/FrameFullscreen'
import DoneScreen from './features/shared/DoneScreen'
import WaitingScreen from './features/shared/WaitingScreen'
import EventEndedScreen from './features/shared/EventEndedScreen'

export default function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/g/:shortCode"                    element={<LandingScreen />} />
        <Route path="/g/:shortCode/camera"             element={<CameraScreen />} />
        <Route path="/g/:shortCode/album"              element={<AlbumScreen />} />
        <Route path="/g/:shortCode/f/:frameIndex"      element={<FrameFullscreen />} />
        <Route path="/g/:shortCode/done"               element={<DoneScreen />} />
        <Route path="/g/:shortCode/waiting"            element={<WaitingScreen />} />
        <Route path="/g/:shortCode/ended"              element={<EventEndedScreen />} />
        <Route path="*" element={<Navigate to="/" replace />} />
      </Routes>
    </BrowserRouter>
  )
}
