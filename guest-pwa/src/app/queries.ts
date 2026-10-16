import { useQuery } from '@tanstack/react-query'
import { hostApi, type EventOut, type InvitedEventOut, type Schemas, type UserOut } from './api/hostClient'

export const qk = {
  me: ['me'] as const,
  events: ['events'] as const,
  invited: ['events', 'invited'] as const,
  event: (id: string) => ['event', id] as const,
  album: (id: string) => ['album', id] as const,
  pricing: ['pricing'] as const,
  entitlements: ['entitlements'] as const,
  collections: ['collections'] as const,
  collection: (id: string) => ['collection', id] as const,
  subscription: ['subscription'] as const,
}

export function useMe() {
  return useQuery({
    queryKey: qk.me,
    queryFn: async () => (await hostApi.get<UserOut>('/users/me')).data,
    staleTime: 60_000,
  })
}

export function useEvents() {
  return useQuery({
    queryKey: qk.events,
    queryFn: async () => (await hostApi.get<EventOut[]>('/events/')).data,
    refetchInterval: 60_000,
  })
}

export function useInvitedEvents() {
  return useQuery({
    queryKey: qk.invited,
    queryFn: async () => (await hostApi.get<InvitedEventOut[]>('/events/invited')).data,
    refetchInterval: 60_000,
  })
}

export function useEvent(id: string) {
  return useQuery({
    queryKey: qk.event(id),
    queryFn: async () => (await hostApi.get<EventOut>(`/events/${id}`)).data,
    refetchInterval: 30_000,
  })
}

export function usePricing() {
  return useQuery({
    queryKey: qk.pricing,
    queryFn: async () => (await hostApi.get<Schemas['PricingOut']>('/pricing')).data,
    staleTime: 10 * 60_000,
  })
}

export function useEntitlements() {
  return useQuery({
    queryKey: qk.entitlements,
    queryFn: async () => (await hostApi.get<Schemas['EntitlementsOut']>('/me/entitlements')).data,
    staleTime: 60_000,
  })
}

export function useCollections() {
  return useQuery({
    queryKey: qk.collections,
    queryFn: async () => (await hostApi.get<Schemas['CollectionsListOut']>('/collections/')).data,
  })
}

export function useCollection(id: string) {
  return useQuery({
    queryKey: qk.collection(id),
    queryFn: async () => (await hostApi.get<Schemas['CollectionOut']>(`/collections/${id}`)).data,
  })
}

export function useSubscription() {
  return useQuery({
    queryKey: qk.subscription,
    queryFn: async () => (await hostApi.get<Schemas['SubscriptionOut']>('/me/subscription')).data,
    staleTime: 30_000,
  })
}

const FREE_QR = new Set(['classic'])
const FREE_FONTS = new Set(['playfair'])

/** Платные стили закрыты замком, пока подписка запущена и у пользователя её нет.
 *  Уже выбранный раньше вариант остаётся доступным. */
export function useStyleLock() {
  const ent = useEntitlements().data
  const gated = !!ent && ent.subscription_enabled && !ent.plus
  return {
    qrLocked: (preset: string, current?: string | null) => gated && !FREE_QR.has(preset) && preset !== current,
    fontLocked: (font: string, current?: string | null) => gated && !FREE_FONTS.has(font) && font !== current,
  }
}
