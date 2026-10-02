import type { PaymentProvider } from './types'
import { MockPaymentProvider } from './mockProvider'
import { EdgePaymentProvider } from './edgeProvider'

let instance: PaymentProvider | null = null

export function getPaymentProvider(): PaymentProvider {
  if (instance) return instance
  const name = (import.meta.env.VITE_PAYMENT_PROVIDER as string) || 'mock'
  instance = name === 'edge' ? new EdgePaymentProvider() : new MockPaymentProvider()
  return instance
}

export function setPaymentProvider(p: PaymentProvider): void { instance = p }
export * from './types'
export { MockPaymentProvider } from './mockProvider'
