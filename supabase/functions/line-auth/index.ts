// Supabase Edge Function `line-auth`
// Exchanges a LINE Login (Web) authorization code for a Supabase session.
// Flow: code -> LINE token endpoint -> LINE ID Token verify (aud + nonce)
//       -> find or create auth user (no merge with existing emails)
//       -> admin.generateLink(magiclink) -> returns a single-use token_hash.
// The browser then calls supabase.auth.verifyOtp({ token_hash, type: 'magiclink' }).
// LINE channel secret and service role never reach the browser.
//
// Deploy:  supabase functions deploy line-auth
// Secrets: supabase secrets set LINE_CHANNEL_ID=... LINE_CHANNEL_SECRET=...
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the runtime.)
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
const LINE_CHANNEL_ID = Deno.env.get('LINE_CHANNEL_ID')!
const LINE_CHANNEL_SECRET = Deno.env.get('LINE_CHANNEL_SECRET')!

const LINE_TOKEN_URL = 'https://api.line.me/oauth2/v2.1/token'
const LINE_VERIFY_URL = 'https://api.line.me/oauth2/v2.1/verify'

const admin = createClient(SUPABASE_URL, SERVICE_ROLE, {
  auth: { persistSession: false, autoRefreshToken: false },
})

const cors = {
  'access-control-allow-origin': '*', // the code is single-use and bound to nonce; no cookies are used
  'access-control-allow-headers': 'authorization, x-client-info, apikey, content-type',
  'access-control-allow-methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'content-type': 'application/json' } })

interface LineIdClaims { sub: string; aud: string; name?: string; email?: string }

/** Authorization code -> LINE id_token. */
async function exchangeCode(code: string, redirectUri: string): Promise<string | null> {
  const res = await fetch(LINE_TOKEN_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      redirect_uri: redirectUri,
      client_id: LINE_CHANNEL_ID,
      client_secret: LINE_CHANNEL_SECRET,
    }),
  })
  if (!res.ok) return null
  const data = (await res.json()) as { id_token?: string }
  return data.id_token ?? null
}

/** LINE verifies signature/expiry; we additionally check aud and nonce (binds the token to this login attempt). */
async function verifyIdToken(idToken: string, nonce: string): Promise<LineIdClaims | null> {
  const res = await fetch(LINE_VERIFY_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ id_token: idToken, client_id: LINE_CHANNEL_ID, nonce }),
  })
  if (!res.ok) return null
  const claims = (await res.json()) as LineIdClaims & { nonce?: string }
  if (claims.aud !== LINE_CHANNEL_ID || !claims.sub) return null
  if (claims.nonce !== undefined && claims.nonce !== nonce) return null
  return claims
}

/**
 * Returns the auth email for the LINE user. A new user always gets an internal email
 * (the LINE email is stored only for reference), so it can never collide with or
 * take over an existing email/password account.
 */
async function findOrCreateUser(claims: LineIdClaims): Promise<{ userId: string; email: string } | null> {
  const authEmail = `line_${claims.sub.toLowerCase()}@line-login.invalid`

  const { data: link } = await admin
    .from('line_identities')
    .select('user_id')
    .eq('line_sub', claims.sub)
    .maybeSingle()

  if (link) {
    await admin.from('line_identities').update({ last_login_at: new Date().toISOString() }).eq('line_sub', claims.sub)
    const { data: existing, error } = await admin.auth.admin.getUserById(link.user_id)
    if (error || !existing.user) return null
    return { userId: existing.user.id, email: existing.user.email ?? authEmail }
  }

  const { data: created, error: createError } = await admin.auth.admin.createUser({
    email: authEmail,
    email_confirm: true,
    // role is always client here; handle_new_user only accepts client|driver and the LINE flow never requests driver
    user_metadata: { full_name: claims.name ?? '', role: 'client', login_provider: 'line' },
  })
  if (createError || !created.user) return null

  const { error: insertError } = await admin.from('line_identities').insert({
    line_sub: claims.sub,
    user_id: created.user.id,
    line_email: claims.email ?? null,
  })
  if (insertError) {
    // Concurrent first login for the same LINE user, or a DB failure: roll back the orphan auth user.
    await admin.auth.admin.deleteUser(created.user.id)
    return null
  }
  return { userId: created.user.id, email: authEmail }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors })
  if (req.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405)

  const body = (await req.json().catch(() => null)) as
    | { code?: unknown; nonce?: unknown; redirectUri?: unknown }
    | null
  if (!body || typeof body.code !== 'string' || typeof body.nonce !== 'string' || typeof body.redirectUri !== 'string') {
    return json({ error: 'INVALID_REQUEST' }, 400)
  }

  const idToken = await exchangeCode(body.code, body.redirectUri)
  if (!idToken) return json({ error: 'LINE_TOKEN_EXCHANGE_FAILED' }, 401)

  const claims = await verifyIdToken(idToken, body.nonce)
  if (!claims) return json({ error: 'LINE_TOKEN_INVALID' }, 401)

  const user = await findOrCreateUser(claims)
  if (!user) return json({ error: 'LINE_LOGIN_FAILED' }, 500)

  const { data: link, error } = await admin.auth.admin.generateLink({ type: 'magiclink', email: user.email })
  const tokenHash = link?.properties?.hashed_token
  if (error || !tokenHash) return json({ error: 'LINE_LOGIN_FAILED' }, 500)

  return json({ tokenHash, type: 'magiclink' })
})
