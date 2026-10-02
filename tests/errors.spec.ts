import { describe, expect, it } from 'vitest'
import { AppError, toAppError } from '@/types/errors'

describe('error mapping', () => {
  it('maps a postgres raise into a typed code', () => {
    const e = toAppError({ message: 'NO_SEATS_AVAILABLE', code: 'P0001' })
    expect(e).toBeInstanceOf(AppError)
    expect(e.code).toBe('NO_SEATS_AVAILABLE')
    expect(e.i18nKey).toBe('errors.NO_SEATS_AVAILABLE')
  })
  it('maps an RLS violation to FORBIDDEN', () => {
    expect(toAppError({ message: 'new row violates row-level security policy', code: '42501' }).code).toBe('FORBIDDEN')
  })
  it('never leaks raw SQL to the UI', () => {
    const e = toAppError({ message: 'duplicate key value violates unique constraint "vehicles_driver_id_key"' })
    expect(e.code).toBe('UNKNOWN')
    expect(e.i18nKey).toBe('errors.UNKNOWN')
  })
  it('is idempotent', () => {
    const e = new AppError('TRIP_UNAVAILABLE')
    expect(toAppError(e)).toBe(e)
  })
})
