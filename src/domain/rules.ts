/**
 * Pure business rules mirrored from the database layer.
 * The DATABASE is the source of truth; these functions exist for instant UI
 * feedback (pre-validation, previews) and are covered by unit tests.
 */
import type { TripCheckpoint, TripSegment } from '@/types'

export interface PricingParams { baseDzd: number; perKmDzd: number; roundingDzd: number }
export const DEFAULT_PRICING: PricingParams = { baseDzd: 50, perKmDzd: 8, roundingDzd: 50 }

export function referencePrice(distanceKm: number, p: PricingParams = DEFAULT_PRICING): number {
  const raw = p.baseDzd + p.perKmDzd * distanceKm
  return Math.round(raw / p.roundingDzd) * p.roundingDzd
}

/** Segments covered by a pickup→dropoff ride on an ordered route. */
export function coveredSegments(
  checkpoints: TripCheckpoint[], segments: TripSegment[], pickupId: string, dropoffId: string,
): TripSegment[] {
  const seq = new Map(checkpoints.map((c) => [c.id, c.sequence]))
  const from = seq.get(pickupId)
  const to = seq.get(dropoffId)
  if (from === undefined || to === undefined) throw new Error('INVALID_CHECKPOINT')
  if (from >= to) throw new Error('INVALID_ROUTE_DIRECTION')
  return segments.filter((s) => {
    const sFrom = seq.get(s.from_checkpoint_id)
    return sFrom !== undefined && sFrom >= from && sFrom < to
  })
}

export function pricePerSeat(
  checkpoints: TripCheckpoint[], segments: TripSegment[], pickupId: string, dropoffId: string,
): number {
  return coveredSegments(checkpoints, segments, pickupId, dropoffId)
    .reduce((sum, s) => sum + Number(s.driver_price), 0)
}

/** Bottleneck availability across every covered segment. */
export function availableSeats(
  checkpoints: TripCheckpoint[], segments: TripSegment[], pickupId: string, dropoffId: string,
): number {
  const covered = coveredSegments(checkpoints, segments, pickupId, dropoffId)
  if (!covered.length) return 0
  return Math.min(...covered.map((s) => s.capacity - s.reserved_seats))
}

export function canReserve(
  checkpoints: TripCheckpoint[], segments: TripSegment[], pickupId: string, dropoffId: string, seats: number,
): boolean {
  return seats > 0 && availableSeats(checkpoints, segments, pickupId, dropoffId) >= seats
}

export interface CancellationPolicy {
  windowHours: number
  minMinutesAfterBooking: number
  refundPercentage: number
}
export const DEFAULT_CANCELLATION: CancellationPolicy = {
  windowHours: 24, minMinutesAfterBooking: 30, refundPercentage: 80,
}

export function cancellationRefund(
  input: { departureAt: Date; bookedAt: Date; now: Date; paidAmount: number; isNoShow?: boolean },
  policy: CancellationPolicy = DEFAULT_CANCELLATION,
): { eligible: boolean; percentage: number; amount: number } {
  if (input.isNoShow) return { eligible: false, percentage: 0, amount: 0 }
  const hoursBefore = (input.departureAt.getTime() - input.now.getTime()) / 3_600_000
  const minutesSinceBooking = (input.now.getTime() - input.bookedAt.getTime()) / 60_000
  const eligible = hoursBefore > policy.windowHours && minutesSinceBooking > policy.minMinutesAfterBooking
  return eligible
    ? { eligible, percentage: policy.refundPercentage, amount: Math.round(input.paidAmount * policy.refundPercentage) / 100 }
    : { eligible: false, percentage: 0, amount: 0 }
}

export function validateResale(
  input: { bookingSeats: number; alreadySold: number; seatsForSale: number; price: number; originalPricePerSeat: number },
): { ok: true } | { ok: false; code: 'INVALID_SEATS' | 'RESALE_PRICE_TOO_HIGH' } {
  if (input.price > input.originalPricePerSeat) return { ok: false, code: 'RESALE_PRICE_TOO_HIGH' }
  if (input.seatsForSale < 1 || input.seatsForSale > input.bookingSeats - input.alreadySold) {
    return { ok: false, code: 'INVALID_SEATS' }
  }
  return { ok: true }
}

export function resaleListingAfterPurchase(
  listing: { seatsForSale: number; seatsSold: number }, bought: number,
): { seatsSold: number; status: 'open' | 'closed' } {
  const sold = listing.seatsSold + bought
  return { seatsSold: sold, status: sold >= listing.seatsForSale ? 'closed' : 'open' }
}

/** A transfer never changes the financial snapshot of a booking. */
export function applyTransfer<T extends { trip_id: string; pickup_checkpoint_id: string; dropoff_checkpoint_id: string; price_per_seat: number; total_amount: number; id: string }>(
  booking: T, target: { tripId: string; pickupId: string; dropoffId: string },
): T {
  return {
    ...booking,
    trip_id: target.tripId,
    pickup_checkpoint_id: target.pickupId,
    dropoff_checkpoint_id: target.dropoffId,
  }
}

export function canCreateResale(input: { bookingStatus: string; hasPendingTransfer: boolean; hasOpenListing: boolean }): boolean {
  return input.bookingStatus === 'confirmed' && !input.hasPendingTransfer && !input.hasOpenListing
}

export function canRequestTransfer(input: { bookingStatus: string; hasPendingTransfer: boolean; hasOpenListing: boolean }): boolean {
  return input.bookingStatus === 'confirmed' && !input.hasPendingTransfer && !input.hasOpenListing
}
