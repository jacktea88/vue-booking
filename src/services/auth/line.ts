/**
 * LINE Login (Web) helpers.
 * Pure functions here are unit-tested. This module must not import the Supabase client.
 * The token exchange happens in the Edge Function `line-auth`; the channel secret never reaches the browser.
 */

const LINE_AUTHORIZE_URL = 'https://access.line.me/oauth2/v2.1/authorize'
const LINE_CALLBACK_PATH = '/auth/line-callback'
const ATTEMPT_KEY = 'line_login_attempt'

export interface LineAttempt {
  state: string
  nonce: string
  redirectPath: string | null
}

export interface LineCallbackParams {
  code: string | null
  state: string | null
  error: string | null
}

export function getLineChannelId(): string | undefined {
  return (import.meta.env.VITE_LINE_CHANNEL_ID as string | undefined)?.trim() || undefined
}

/** The LINE button is shown only when VITE_LINE_CHANNEL_ID is configured. */
export function isLineLoginEnabled(): boolean {
  return Boolean(getLineChannelId())
}

/** Must match the Callback URL registered in the LINE Login channel. */
export function lineRedirectUri(origin: string = window.location.origin): string {
  return `${origin}${LINE_CALLBACK_PATH}`
}

export function randomToken(bytes = 16): string {
  const buf = new Uint8Array(bytes)
  crypto.getRandomValues(buf)
  return Array.from(buf, (b) => b.toString(16).padStart(2, '0')).join('')
}

export function buildLineAuthorizeUrl(params: {
  channelId: string
  redirectUri: string
  state: string
  nonce: string
}): string {
  const query = new URLSearchParams({
    response_type: 'code',
    client_id: params.channelId,
    redirect_uri: params.redirectUri,
    state: params.state,
    scope: 'openid profile email',
    nonce: params.nonce,
  })
  return `${LINE_AUTHORIZE_URL}?${query.toString()}`
}

/** Only same-origin relative paths are allowed (blocks open redirects such as `//evil.example`). */
export function safeInternalPath(value: unknown): string | null {
  if (typeof value !== 'string') return null
  if (!value.startsWith('/') || value.startsWith('//') || value.startsWith('/\\')) return null
  return value
}

export function parseLineCallback(search: string): LineCallbackParams {
  const query = new URLSearchParams(search)
  return {
    code: query.get('code'),
    state: query.get('state'),
    error: query.get('error'),
  }
}

/** Saves state/nonce before leaving the app (sessionStorage, cleared on tab close). */
export function startLineLogin(redirectPath: string | null): string {
  const channelId = getLineChannelId()
  if (!channelId) throw new Error('VITE_LINE_CHANNEL_ID is not configured')

  const attempt: LineAttempt = {
    state: randomToken(),
    nonce: randomToken(),
    redirectPath: safeInternalPath(redirectPath),
  }
  sessionStorage.setItem(ATTEMPT_KEY, JSON.stringify(attempt))
  return buildLineAuthorizeUrl({
    channelId,
    redirectUri: lineRedirectUri(),
    state: attempt.state,
    nonce: attempt.nonce,
  })
}

/** Reads and always clears the pending attempt. Returns null when the state does not match (CSRF guard). */
export function takeLineAttempt(state: string): LineAttempt | null {
  const raw = sessionStorage.getItem(ATTEMPT_KEY)
  sessionStorage.removeItem(ATTEMPT_KEY)
  if (!raw) return null
  try {
    const attempt = JSON.parse(raw) as LineAttempt
    return attempt.state === state ? attempt : null
  } catch {
    return null
  }
}
