/** Typed application errors. Raw database errors are never shown to end users. */
export const APP_ERROR_CODES = [
  'UNAUTHENTICATED', 'FORBIDDEN', 'NOT_FOUND', 'NETWORK',
  'DRIVER_NOT_VERIFIED', 'VEHICLE_REQUIRED', 'AT_LEAST_TWO_CHECKPOINTS', 'DEPARTURE_IN_PAST',
  'TRIP_ALREADY_PUBLISHED', 'INVALID_TRIP_STATE', 'TRIP_UNAVAILABLE',
  'NO_SEATS_AVAILABLE', 'INVALID_SEATS', 'INVALID_ROUTE', 'INVALID_ROUTE_DIRECTION',
  'INVALID_CHECKPOINT', 'INVALID_PRICE', 'INVALID_RATING',
  'DRIVER_CANNOT_BOOK_OWN_TRIP', 'INVALID_BOOKING_STATE', 'BOOKING_EXPIRED',
  'BOOKING_PRICE_IMMUTABLE', 'PAYMENT_NOT_AUTHORIZED', 'PAYMENT_FAILED',
  'RESALE_UNAVAILABLE', 'RESALE_ALREADY_OPEN', 'RESALE_PRICE_TOO_HIGH', 'RESALE_IN_PROGRESS',
  'CANNOT_BUY_OWN_RESALE', 'TRANSFER_UNAVAILABLE', 'TRANSFER_ALREADY_PENDING',
  'TRANSFER_IN_PROGRESS', 'BOOKING_NOT_COMPLETED', 'FORBIDDEN_FIELD_UPDATE', 'UNKNOWN',
] as const

export type AppErrorCode = (typeof APP_ERROR_CODES)[number]

export class AppError extends Error {
  readonly code: AppErrorCode
  readonly cause?: unknown
  constructor(code: AppErrorCode, cause?: unknown) {
    super(code)
    this.name = 'AppError'
    this.code = code
    this.cause = cause
  }
  /** i18n key used by the UI. */
  get i18nKey(): string { return `errors.${this.code}` }
}

const CODE_SET = new Set<string>(APP_ERROR_CODES as readonly string[])

/** Maps a Supabase/Postgres error into a typed AppError without leaking SQL details. */
export function toAppError(err: unknown): AppError {
  if (err instanceof AppError) return err
  const anyErr = err as { message?: string; code?: string; details?: string } | null
  const raw = `${anyErr?.message ?? ''} ${anyErr?.details ?? ''}`
  const found = APP_ERROR_CODES.find((c) => raw.includes(c))
  if (found) return new AppError(found, err)
  if (anyErr?.code === '42501') return new AppError('FORBIDDEN', err)
  if (anyErr?.code === 'PGRST116') return new AppError('NOT_FOUND', err)
  if (CODE_SET.has(anyErr?.message ?? '')) return new AppError(anyErr!.message as AppErrorCode, err)
  if (typeof anyErr?.message === 'string' && /fetch|network/i.test(anyErr.message)) return new AppError('NETWORK', err)
  return new AppError('UNKNOWN', err)
}
