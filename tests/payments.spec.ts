import { beforeEach, describe, expect, it, vi } from 'vitest'
import { bookingService } from '@/services/domain/bookingService'
import { setPaymentProvider } from '@/services/payments'
import { AppError } from '@/types/errors'
import type { PaymentProvider } from '@/services/payments'

function fakeProvider(overrides: Partial<PaymentProvider> = {}) {
  const base: PaymentProvider = {
    id: 'fake',
    createPayment: vi.fn(async (i) => ({ paymentId: i.paymentId, bookingId: i.bookingId, amount: i.amount, currency: 'DZD', status: 'requires_payment' as const })),
    authorizePayment: vi.fn(async (id) => ({ paymentId: id, bookingId: 'b', amount: 0, currency: 'DZD', status: 'authorized' as const })),
    capturePayment: vi.fn(async (id) => ({ paymentId: id, bookingId: 'b', amount: 0, currency: 'DZD', status: 'paid' as const })),
    refundPayment: vi.fn(async (id) => ({ paymentId: id, bookingId: 'b', amount: 0, currency: 'DZD', status: 'refunded' as const })),
    getPaymentStatus: vi.fn(async () => 'paid' as const),
  }
  const p = { ...base, ...overrides }
  setPaymentProvider(p)
  return p
}

describe('payment flow', () => {
  beforeEach(() => vi.clearAllMocks())

  it('captures immediately for auto_confirm trips', async () => {
    const p = fakeProvider()
    const r = await bookingService.payBooking({ payment_id: 'p1', booking_id: 'b1', amount: 1000, booking_mode: 'auto_confirm' })
    expect(p.capturePayment).toHaveBeenCalledWith('p1')
    expect(p.authorizePayment).not.toHaveBeenCalled()
    expect(r.status).toBe('paid')
  })

  it('only authorizes (holds) for driver_approval trips', async () => {
    const p = fakeProvider()
    const r = await bookingService.payBooking({ payment_id: 'p2', booking_id: 'b2', amount: 1000, booking_mode: 'driver_approval' })
    expect(p.authorizePayment).toHaveBeenCalledWith('p2')
    expect(p.capturePayment).not.toHaveBeenCalled()
    expect(r.status).toBe('authorized')
  })

  it('surfaces a typed error on payment failure', async () => {
    fakeProvider({ capturePayment: vi.fn(async (id: string) => ({ paymentId: id, bookingId: 'b', amount: 0, currency: 'DZD', status: 'failed' as const })) })
    await expect(bookingService.payBooking({ payment_id: 'p3', booking_id: 'b3', amount: 500, booking_mode: 'auto_confirm' }))
      .rejects.toBeInstanceOf(AppError)
  })

  it('treats an expired payment as a failure', async () => {
    fakeProvider({ capturePayment: vi.fn(async (id: string) => ({ paymentId: id, bookingId: 'b', amount: 0, currency: 'DZD', status: 'expired' as const })) })
    await expect(bookingService.payBooking({ payment_id: 'p4', booking_id: 'b4', amount: 500, booking_mode: 'auto_confirm' }))
      .rejects.toMatchObject({ code: 'PAYMENT_FAILED' })
  })
})
