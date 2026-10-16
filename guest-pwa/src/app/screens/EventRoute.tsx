import { useParams } from 'react-router-dom'
import { apiErrorMessage } from '../api/hostClient'
import { useEvent } from '../queries'
import { CenterSpinner, ErrorBox, TopBar } from '../ui'
import EventScreen from './EventScreen'
import SoloScreen from './SoloScreen'

/** Один маршрут для обоих типов альбомов: соло или событие с гостями. */
export default function EventRoute() {
  const { id = '' } = useParams()
  const event = useEvent(id)
  if (event.isLoading) return (<><TopBar back="/app" title="Альбом" /><CenterSpinner /></>)
  if (event.error || !event.data) {
    return (<><TopBar back="/app" title="Альбом" /><main className="host-main"><ErrorBox message={apiErrorMessage(event.error, 'Альбом не найден')} onRetry={() => void event.refetch()} /></main></>)
  }
  return event.data.kind === 'solo' ? <SoloScreen /> : <EventScreen />
}
