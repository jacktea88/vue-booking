import { rpc, query } from '@/services/supabase/rpc'
import { supabase } from '@/services/supabase/client'
import type { PaymentStatus } from '@/types'
import type { CreatePaymentInput, PaymentIntent, PaymentProvider } from './types'

/**
 * Development provider. The *state transition* still happens server-side in
 * `apply_payment_result` (guarded by the `allow_mock_payments` setting), so the
 * client can never forge a payment state in production.
 */
export class MockPaymentProvider implements PaymentProvider {
  readonly id = 'mock'

  async createPayment(input: CreatePaymentInput): Promise<PaymentIntent> {
    return {
      paymentId: input.paymentId,
      bookingId: input.bookingId,
      amount: input.amount,
      currency: input.currency ?? 'DZD',
      status: 'requires_payment',
    }
  }

  private async apply(paymentId: string, status: PaymentStatus): Promise<PaymentIntent> {
    const res = await rpc<{ payment_status: PaymentStatus; booking_id: string }>('apply_payment_result', {
      p_payment: paymentId, p_new_status: status, p_provider_reference: `mock_${Date.now()}`,
    })
    return { paymentId, bookingId: res.booking_id, amount: 0, currency: 'DZD', status: res.payment_status }
  }

  authorizePayment(paymentId: string) { return this.apply(paymentId, 'authorized') }
  capturePayment(paymentId: string) { return this.apply(paymentId, 'paid') }
  async failPayment(paymentId: string) { return this.apply(paymentId, 'failed') }
  async refundPayment(paymentId: string) { return this.apply(paymentId, 'refunded') }

  async getPaymentStatus(paymentId: string): Promise<PaymentStatus> {
    const row = await query<{ status: PaymentStatus }>(() =>
      supabase.from('booking_payments').select('status').eq('id', paymentId).single())
    return row.status
  }
}
