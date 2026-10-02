import type { PaymentStatus } from '@/types'

export interface PaymentIntent {
  paymentId: string
  bookingId: string
  amount: number
  currency: string
  /** Set when the provider requires a redirect/3DS step. */
  redirectUrl?: string
  status: PaymentStatus
  providerReference?: string
}

export interface CreatePaymentInput {
  paymentId: string
  bookingId: string
  amount: number
  currency?: string
  /** auto_confirm captures immediately, driver_approval only authorizes (hold). */
  capture: boolean
}

/** Provider-agnostic payment contract. No provider SDK leaks into UI code. */
export interface PaymentProvider {
  readonly id: string
  createPayment(input: CreatePaymentInput): Promise<PaymentIntent>
  authorizePayment(paymentId: string): Promise<PaymentIntent>
  capturePayment(paymentId: string): Promise<PaymentIntent>
  refundPayment(paymentId: string, amount: number): Promise<PaymentIntent>
  getPaymentStatus(paymentId: string): Promise<PaymentStatus>
}
