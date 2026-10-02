// Supabase Edge Function `payments`
// Holds ALL payment-provider secrets. The browser never sees them.
// Deploy: supabase functions deploy payments
// Secrets: supabase secrets set PAYMENT_PROVIDER_KEY=... SUPABASE_SERVICE_ROLE_KEY=...
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SERVICE_ROLE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const admin = createClient(SUPABASE_URL, SERVICE_ROLE, { auth: { persistSession: false } })

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } })

/** Replace this with the real PSP integration (CIB/Edahabia/Stripe…). */
async function providerCall(action: string, paymentId: string, amount?: number) {
  return { reference: `${action}_${paymentId}_${Date.now()}`, ok: true, amount }
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405)

  // Caller identity comes from the verified JWT, never from the body.
  const authHeader = req.headers.get('Authorization') ?? ''
  const { data: userData } = await admin.auth.getUser(authHeader.replace('Bearer ', ''))
  if (!userData?.user) return json({ error: 'UNAUTHENTICATED' }, 401)

  const body = await req.json().catch(() => ({}))
  const { action, paymentId, amount } = body as { action?: string; paymentId?: string; amount?: number }
  if (!action || !paymentId) return json({ error: 'INVALID_REQUEST' }, 400)

  // Ownership check: the payment must belong to the caller's booking.
  const { data: pay } = await admin
    .from('booking_payments')
    .select('id, amount, status, booking_id, bookings!inner(client_id)')
    .eq('id', paymentId)
    .single()
  if (!pay) return json({ error: 'NOT_FOUND' }, 404)
  const ownerId = (pay as any).bookings?.client_id
  if (ownerId !== userData.user.id) return json({ error: 'FORBIDDEN' }, 403)

  const nextStatus: Record<string, string> = {
    create: 'requires_payment', authorize: 'authorized', capture: 'paid', refund: 'refunded',
  }

  if (action === 'status') return json({ status: pay.status })
  if (!(action in nextStatus)) return json({ error: 'INVALID_REQUEST' }, 400)

  const res = await providerCall(action, paymentId, amount)
  if (!res.ok) {
    await admin.rpc('apply_payment_result', { p_payment: paymentId, p_new_status: 'failed', p_provider_reference: res.reference })
    return json({ status: 'failed' })
  }
  if (action === 'create') return json({ paymentId, bookingId: pay.booking_id, amount: pay.amount, currency: 'DZD', status: 'requires_payment' })

  // State transition executed server-side with the service role.
  const { data, error } = await admin.rpc('apply_payment_result', {
    p_payment: paymentId, p_new_status: nextStatus[action], p_provider_reference: res.reference,
  })
  if (error) return json({ error: 'PAYMENT_FAILED', detail: error.message }, 400)
  return json({ paymentId, bookingId: pay.booking_id, amount: pay.amount, currency: 'DZD', status: (data as any)?.payment_status })
})
