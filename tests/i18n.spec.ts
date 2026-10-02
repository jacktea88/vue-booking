import { describe, expect, it } from 'vitest'
import en from '@/i18n/en'
import fr from '@/i18n/fr'
import ar from '@/i18n/ar'
import { APP_ERROR_CODES } from '@/types/errors'

function keys(obj: Record<string, any>, prefix = ''): string[] {
  return Object.entries(obj).flatMap(([k, v]) =>
    v && typeof v === 'object' ? keys(v, `${prefix}${k}.`) : [`${prefix}${k}`])
}

describe('i18n', () => {
  it('fr and ar cover every en key', () => {
    const base = keys(en).sort()
    expect(keys(fr).sort()).toEqual(base)
    expect(keys(ar).sort()).toEqual(base)
  })
  it('has a translation for every typed error code', () => {
    for (const code of APP_ERROR_CODES) {
      expect(en.errors[code as keyof typeof en.errors], code).toBeTruthy()
      expect((ar.errors as Record<string, string>)[code], code).toBeTruthy()
    }
  })
})
