import type { GeoPoint } from '@/types'

const EARTH_RADIUS_KM = 6371

/** Great-circle distance in km (used as the offline fallback for routing). */
export function haversineKm(a: GeoPoint, b: GeoPoint): number {
  const toRad = (d: number) => (d * Math.PI) / 180
  const dLat = toRad(b.lat - a.lat)
  const dLng = toRad(b.lng - a.lng)
  const lat1 = toRad(a.lat)
  const lat2 = toRad(b.lat)
  const h = Math.sin(dLat / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.min(1, Math.sqrt(h)))
}

export const ROAD_FACTOR = 1.25
export const DEFAULT_SPEED_KMH = 70

export function estimateMinutes(distanceKm: number, speedKmh = DEFAULT_SPEED_KMH): number {
  return Math.max(1, Math.ceil((distanceKm / speedKmh) * 60))
}
