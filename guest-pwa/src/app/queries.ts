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
