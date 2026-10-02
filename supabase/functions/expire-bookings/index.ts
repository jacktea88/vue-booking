// Scheduled Edge Function: releases seats + payment holds for driver-approval
// bookings that were not answered within the configurable timeout.
// Schedule with pg_cron or an external scheduler (every 5 minutes).
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
  auth: { persistSession: false },
})

Deno.serve(async () => {
  const { data, error } = await admin.rpc('expire_pending_bookings')
  if (error) return new Response(JSON.stringify({ error: error.message }), { status: 500 })
  return new Response(JSON.stringify({ expired: data }), { headers: { 'content-type': 'application/json' } })
})
