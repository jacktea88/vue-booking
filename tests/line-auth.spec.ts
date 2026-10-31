import { describe, expect, it } from 'vitest'
import {
  buildLineAuthorizeUrl,
  parseLineCallback,
  randomToken,
  safeInternalPath,
} from '@/services/auth/line'

describe('LINE login helpers', () => {
  it('builds an authorize URL with state, nonce and openid scope', () => {
    const url = new URL(buildLineAuthorizeUrl({
      channelId: '1234567890',
      redirectUri: 'http://localhost:5173/auth/line-callback',
      state: 'st',
      nonce: 'no',
    }))
    expect(url.origin + url.pathname).toBe('https://access.line.me/oauth2/v2.1/authorize')
    expect(url.searchParams.get('response_type')).toBe('code')
    expect(url.searchParams.get('client_id')).toBe('1234567890')
    expect(url.searchParams.get('redirect_uri')).toBe('http://localhost:5173/auth/line-callback')
    expect(url.searchParams.get('state')).toBe('st')
    expect(url.searchParams.get('nonce')).toBe('no')
    expect(url.searchParams.get('scope')).toContain('openid')
  })

  it('parses code and state from the callback query', () => {
    expect(parseLineCallback('?code=abc&state=xyz')).toEqual({ code: 'abc', state: 'xyz', error: null })
  })

  it('parses LINE error responses (e.g. user cancelled)', () => {
    expect(parseLineCallback('?error=access_denied&state=xyz')).toEqual({
      code: null, state: 'xyz', error: 'access_denied',
    })
  })

  it('returns nulls for an empty query', () => {
    expect(parseLineCallback('')).toEqual({ code: null, state: null, error: null })
  })

  it('allows only same-origin relative paths as post-login redirects', () => {
    expect(safeInternalPath('/bookings')).toBe('/bookings')
    expect(safeInternalPath('/trips/1?x=1')).toBe('/trips/1?x=1')
    expect(safeInternalPath('//evil.example')).toBeNull()
    expect(safeInternalPath('/\\evil.example')).toBeNull()
    expect(safeInternalPath('https://evil.example')).toBeNull()
    expect(safeInternalPath(undefined)).toBeNull()
    expect(safeInternalPath(['/a'])).toBeNull()
  })

  it('generates hex tokens of the requested length and unique values', () => {
    const a = randomToken()
    const b = randomToken()
    expect(a).toMatch(/^[0-9a-f]{32}$/)
    expect(a).not.toBe(b)
    expect(randomToken(8)).toMatch(/^[0-9a-f]{16}$/)
  })
})
