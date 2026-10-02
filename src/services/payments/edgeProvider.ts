import { supabase } from '@/services/supabase/client'
import { toAppError } from '@/types/errors'
import type { PaymentStatus } from '@/types'
import type { CreatePaymentInput, PaymentIntent, PaymentProvider } from './types'

/**
 * Real-provider adapter: all secrets live in the Supabase Edge Function `payments`.
 * The browser only ever sees an intent + redirect URL.
 */
export class EdgePaymentProvider implements PaymentProvider {
  readonly id = 'edge'

  private async call<T>(action: string, payload: Record<string, unknown>): Promise<T> {
    const { data, error } = await supabase.functions.invoke('payments', { body: { action, ...payload } })
    if (error) throw toAppError(error)
    return data as T
  }

  createPayment(input: CreatePaymentInput) { return this.call<PaymentIntent>('create', { ...input }) }
  authorizePayment(paymentId: string) { return this.call<PaymentIntent>('authorize', { paymentId }) }
  capturePayment(paymentId: string) { return this.call<PaymentIntent>('capture', { paymentId }) }
  refundPayment(paymentId: string, amount: number) { return this.call<PaymentIntent>('refund', { paymentId, amount }) }
  async getPaymentStatus(paymentId: string) {
    const r = await this.call<{ status: PaymentStatus }>('status', { paymentId })
    return r.status
  }
}
