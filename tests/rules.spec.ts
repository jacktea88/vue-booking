import { describe, expect, it } from 'vitest'
import {
  applyTransfer, availableSeats, canCreateResale, canRequestTransfer, canReserve, cancellationRefund,
  coveredSegments, pricePerSeat, referencePrice, resaleListingAfterPurchase, validateResale,
} from '@/domain/rules'
import { makeRoute } from './helpers'

describe('pricing', () => {
  it('computes a rounded reference price from distance', () => {
    expect(referencePrice(0)).toBe(50)
    expect(referencePrice(100)).toBe(850)
  })

  it('sums segment prices for a multi-segment booking (A→D = AB+BC+CD)', () => {
    const { checkpoints, segments } = makeRoute()
    expect(pricePerSeat(checkpoints, segments, 'cp0', 'cp3')).toBe(2400)
    expect(pricePerSeat(checkpoints, segments, 'cp1', 'cp3')).toBe(1900)
  })
})

describe('route matching / checkpoint ordering', () => {
  it('derives adjacent segments covered by a ride', () => {
    const { checkpoints, segments } = makeRoute()
    expect(coveredSegments(checkpoints, segments, 'cp0', 'cp2').map((s) => s.id)).toEqual(['sg0', 'sg1'])
  })

  it('rejects a reversed route', () => {
    const { checkpoints, segments } = makeRoute()
    expect(() => coveredSegments(checkpoints, segments, 'cp3', 'cp0')).toThrow('INVALID_ROUTE_DIRECTION')
  })

  it('rejects an unknown checkpoint', () => {
    const { checkpoints, segments } = makeRoute()
    expect(() => coveredSegments(checkpoints, segments, 'nope', 'cp2')).toThrow('INVALID_CHECKPOINT')
  })
})

describe('seat availability (overbooking prevention)', () => {
  it('uses the bottleneck segment across the whole ride', () => {
    const { checkpoints, segments } = makeRoute(4)
    segments[1].reserved_seats = 3
    expect(availableSeats(checkpoints, segments, 'cp0', 'cp3')).toBe(1)
    expect(availableSeats(checkpoints, segments, 'cp2', 'cp3')).toBe(4)
  })

  it('refuses a booking exceeding availability', () => {
    const { checkpoints, segments } = makeRoute(4)
    segments[2].reserved_seats = 4
    expect(canReserve(checkpoints, segments, 'cp0', 'cp3', 1)).toBe(false)
    expect(canReserve(checkpoints, segments, 'cp0', 'cp2', 1)).toBe(true)
  })
})

describe('cancellation policy', () => {
  const now = new Date('2026-01-10T10:00:00Z')
  it('refunds 80% when eligible', () => {
    const r = cancellationRefund({
      departureAt: new Date('2026-01-12T10:00:00Z'), bookedAt: new Date('2026-01-10T09:00:00Z'), now, paidAmount: 2000,
    })
    expect(r).toEqual({ eligible: true, percentage: 80, amount: 1600 })
  })
  it('refuses a refund inside the 24h window', () => {
    const r = cancellationRefund({
      departureAt: new Date('2026-01-10T20:00:00Z'), bookedAt: new Date('2026-01-09T09:00:00Z'), now, paidAmount: 2000,
    })
    expect(r.eligible).toBe(false)
    expect(r.amount).toBe(0)
  })
  it('refuses a refund within 30 minutes of booking', () => {
    const r = cancellationRefund({
      departureAt: new Date('2026-01-20T10:00:00Z'), bookedAt: new Date('2026-01-10T09:45:00Z'), now, paidAmount: 1000,
    })
    expect(r.eligible).toBe(false)
  })
  it('gives 0% for a no-show', () => {
    const r = cancellationRefund({
      departureAt: new Date('2026-01-20T10:00:00Z'), bookedAt: new Date('2026-01-01T09:00:00Z'),
      now, paidAmount: 5000, isNoShow: true,
    })
    expect(r).toEqual({ eligible: false, percentage: 0, amount: 0 })
  })
})

describe('resale', () => {
  it('allows a partial resale', () => {
    expect(validateResale({ bookingSeats: 3, alreadySold: 0, seatsForSale: 2, price: 700, originalPricePerSeat: 1000 }))
      .toEqual({ ok: true })
  })
  it('refuses selling more seats than owned', () => {
    expect(validateResale({ bookingSeats: 3, alreadySold: 2, seatsForSale: 2, price: 700, originalPricePerSeat: 1000 }))
      .toEqual({ ok: false, code: 'INVALID_SEATS' })
  })
  it('refuses a price above the original seat price', () => {
    expect(validateResale({ bookingSeats: 3, alreadySold: 0, seatsForSale: 1, price: 1200, originalPricePerSeat: 1000 }))
      .toEqual({ ok: false, code: 'RESALE_PRICE_TOO_HIGH' })
  })
  it('keeps the listing open on a partial purchase and closes it when fully sold', () => {
    expect(resaleListingAfterPurchase({ seatsForSale: 2, seatsSold: 0 }, 1)).toEqual({ seatsSold: 1, status: 'open' })
    expect(resaleListingAfterPurchase({ seatsForSale: 2, seatsSold: 1 }, 1)).toEqual({ seatsSold: 2, status: 'closed' })
  })
  it('blocks resale while a transfer is pending, and restores it afterwards', () => {
    expect(canCreateResale({ bookingStatus: 'confirmed', hasPendingTransfer: true, hasOpenListing: false })).toBe(false)
    expect(canCreateResale({ bookingStatus: 'confirmed', hasPendingTransfer: false, hasOpenListing: false })).toBe(true)
  })
})

describe('transfer', () => {
  const booking = {
    id: 'b1', trip_id: 't1', pickup_checkpoint_id: 'cp0', dropoff_checkpoint_id: 'cp3',
    price_per_seat: 2400, total_amount: 4800,
  }
  it('moves the booking without creating a new one and preserves the price', () => {
    const moved = applyTransfer(booking, { tripId: 't2', pickupId: 'x0', dropoffId: 'x2' })
    expect(moved.id).toBe('b1')
    expect(moved.trip_id).toBe('t2')
    expect(moved.pickup_checkpoint_id).toBe('x0')
    expect(moved.price_per_seat).toBe(2400)
    expect(moved.total_amount).toBe(4800)
  })
  it('blocks a transfer when a resale listing is open', () => {
    expect(canRequestTransfer({ bookingStatus: 'confirmed', hasPendingTransfer: false, hasOpenListing: true })).toBe(false)
  })
  it('blocks a transfer on a non-confirmed booking', () => {
    expect(canRequestTransfer({ bookingStatus: 'pending', hasPendingTransfer: false, hasOpenListing: false })).toBe(false)
  })
})
