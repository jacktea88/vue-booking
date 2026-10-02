import type { TripCheckpoint, TripSegment } from '@/types'

/** Alger → Blida → Médéa → Laghouat route used across the business-rule tests. */
export function makeRoute(capacity = 4): { checkpoints: TripCheckpoint[]; segments: TripSegment[] } {
  const names = ['Alger', 'Blida', 'Médéa', 'Laghouat']
  const checkpoints: TripCheckpoint[] = names.map((name, i) => ({
    id: `cp${i}`, name, sequence: i, estimated_arrival: null, lat: 36 - i, lng: 3,
  }))
  const prices = [500, 400, 1500]
  const segments: TripSegment[] = prices.map((price, i) => ({
    id: `sg${i}`, sequence: i, from_checkpoint_id: `cp${i}`, to_checkpoint_id: `cp${i + 1}`,
    distance_km: 50 * (i + 1), estimated_minutes: 45 * (i + 1),
    reference_price: price, driver_price: price, capacity, reserved_seats: 0,
  }))
  return { checkpoints, segments }
}
