-- 0022_approval_only.sql
-- Removes online payment from the booking flow. Approval (driver / admin) decides whether an order is valid.
--
-- Behaviour after this migration:
--   * auto_confirm trips  -> booking is confirmed immediately (no payment).
--   * driver_approval     -> booking stays pending until driver/admin confirms, rejects, or it expires.
--   * Cancellation        -> allowed only before (departure - cancellation_window_hours); no refund.
--   * Resale purchase     -> buyer booking is always pending and needs driver/admin approval.
--   * Trip cancellation   -> bookings are cancelled without any refund bookkeeping.
--
-- booking_payments, apply_payment_result() and historical payment rows are intentionally kept.
-- The client no longer creates or reads payment intents; the Edge Function `payments` is unused.

----------------------------------------------------------------------
-- Booking creation (atomic seat reservation + price snapshot + status by booking mode)
----------------------------------------------------------------------
create or replace function public.create_booking(
  p_trip uuid, p_pickup uuid, p_dropoff uuid, p_seats int, p_source booking_source default 'direct'
) returns jsonb language plpgsql security definer set search_path = public, app as $$
declare v_client uuid := auth.uid(); t record; v_price numeric; v_booking uuid; v_status booking_status;
begin
  if v_client is null then raise exception 'UNAUTHENTICATED' using errcode='P0001'; end if;
  if p_seats is null or p_seats < 1 then raise exception 'INVALID_SEATS' using errcode='P0001'; end if;

  select * into t from public.trips where id = p_trip for update;
  if t is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if t.status <> 'published' then raise exception 'TRIP_UNAVAILABLE' using errcode='P0001'; end if;
  if t.departure_at <= now() then raise exception 'TRIP_UNAVAILABLE' using errcode='P0001'; end if;
  if t.driver_id = v_client then raise exception 'DRIVER_CANNOT_BOOK_OWN_TRIP' using errcode='P0001'; end if;

  -- price snapshot (server-side only; frontend price is never trusted)
  v_price := app.segment_price_sum(p_trip, p_pickup, p_dropoff);
  if v_price <= 0 then raise exception 'INVALID_ROUTE' using errcode='P0001'; end if;

  perform app.move_seats(p_trip, p_pickup, p_dropoff, p_seats);  -- locks + verifies capacity

  v_status := case when t.booking_mode = 'auto_confirm' then 'confirmed' else 'pending' end;

  insert into public.bookings(client_id, trip_id, pickup_checkpoint_id, dropoff_checkpoint_id,
                              seats, price_per_seat, total_amount, status, source, approval_expires_at)
  values (v_client, p_trip, p_pickup, p_dropoff, p_seats, v_price, v_price * p_seats, v_status, p_source,
          case when v_status = 'pending'
               then now() + make_interval(mins => app.setting_int('booking_approval_timeout_minutes',30)) end)
  returning id into v_booking;

  perform app.audit('create_booking','booking',v_booking,
    jsonb_build_object('trip_id',p_trip,'seats',p_seats,'total',v_price*p_seats,'source',p_source,'status',v_status));

  if v_status = 'pending' then
    perform app.notify(t.driver_id,'booking_request','notifications.booking_request.title','notifications.booking_request.body',
      jsonb_build_object('booking_id', v_booking, 'trip_id', p_trip));
  else
    perform app.notify(v_client,'booking_confirmed','notifications.booking_confirmed.title','notifications.booking_confirmed.body',
      jsonb_build_object('booking_id', v_booking));
    perform app.notify(t.driver_id,'booking_confirmed','notifications.booking_confirmed.title','notifications.booking_confirmed.body',
      jsonb_build_object('booking_id', v_booking));
  end if;

  return jsonb_build_object('booking_id', v_booking, 'amount', v_price * p_seats, 'price_per_seat', v_price,
                            'booking_mode', t.booking_mode, 'status', v_status);
end; $$;

----------------------------------------------------------------------
-- Driver / admin approval
----------------------------------------------------------------------
create or replace function public.confirm_booking(p_booking uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare b record; t record;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id;
  if t.driver_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status <> 'pending' then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;
  if b.approval_expires_at is not null and b.approval_expires_at < now() then
    raise exception 'BOOKING_EXPIRED' using errcode='P0001'; end if;

  update public.bookings set status='confirmed', approval_expires_at=null where id = b.id;
  perform app.audit('confirm_booking','booking',b.id,'{}'::jsonb);
  perform app.notify(b.client_id,'booking_accepted','notifications.booking_accepted.title','notifications.booking_accepted.body',
    jsonb_build_object('booking_id',b.id));
end; $$;

create or replace function public.reject_booking(p_booking uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public, app as $$
declare b record; t record;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id;
  if t.driver_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status <> 'pending' then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;

  perform app.move_seats(b.trip_id, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
  update public.bookings set status='rejected', approval_expires_at=null where id = b.id;

  perform app.audit('reject_booking','booking',b.id, jsonb_build_object('reason',p_reason));
  perform app.notify(b.client_id,'booking_rejected','notifications.booking_rejected.title','notifications.booking_rejected.body',
    jsonb_build_object('booking_id',b.id));
end; $$;

-- Expire stale driver-approval bookings (call from cron / Edge Function).
create or replace function public.expire_pending_bookings()
returns int language plpgsql security definer set search_path = public, app as $$
declare b record; n int := 0;
begin
  for b in select * from public.bookings
            where status='pending' and approval_expires_at is not null and approval_expires_at < now()
            for update loop
    perform app.move_seats(b.trip_id, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
    update public.bookings set status='rejected', approval_expires_at=null where id = b.id;
    perform app.audit('expire_booking','booking',b.id,'{}'::jsonb);
    perform app.notify(b.client_id,'booking_rejected','notifications.booking_expired.title','notifications.booking_expired.body',
      jsonb_build_object('booking_id',b.id));
    n := n + 1;
  end loop;
  return n;
end; $$;

----------------------------------------------------------------------
-- Cancellation: non-monetary rule only. Allowed until departure - cancellation_window_hours.
-- Admins may cancel at any time.
----------------------------------------------------------------------
create or replace function public.cancellation_quote(p_booking uuid)
returns jsonb language plpgsql stable security definer set search_path = public, app as $$
declare b record; t record; v_hours numeric; v_cutoff timestamptz;
begin
  select * into b from public.bookings where id = p_booking;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if b.client_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  select * into t from public.trips where id = b.trip_id;
  v_hours  := app.setting_num('cancellation_window_hours',24);
  v_cutoff := t.departure_at - make_interval(hours => v_hours::int);
  return jsonb_build_object(
    'eligible', b.status in ('pending','confirmed') and now() < v_cutoff,
    'cutoff_at', v_cutoff,
    'window_hours', v_hours);
end; $$;

create or replace function public.cancel_booking(p_booking uuid)
returns jsonb language plpgsql security definer set search_path = public, app as $$
declare b record; q jsonb;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if b.client_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status not in ('pending','confirmed') then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;

  q := public.cancellation_quote(p_booking);
  if not (q->>'eligible')::boolean and not app.is_admin() then
    raise exception 'CANCELLATION_WINDOW_CLOSED' using errcode='P0001'; end if;

  perform app.move_seats(b.trip_id, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
  update public.bookings set status='cancelled', approval_expires_at=null where id = b.id;
  update public.transfer_requests set status='cancelled', responded_at=now() where booking_id=b.id and status='pending';
  update public.resale_listings set status='cancelled', closed_at=now() where booking_id=b.id and status='open';

  perform app.audit('cancel_booking','booking',b.id, q);
  perform app.notify(
    (select t.driver_id from public.trips t where t.id = b.trip_id),
    'booking_cancelled','notifications.booking_cancelled.title','notifications.booking_cancelled.body',
    jsonb_build_object('booking_id',b.id));
  return jsonb_build_object('cancelled', true);
end; $$;

----------------------------------------------------------------------
-- Resale: buyer booking always waits for driver / admin approval.
-- Seat inventory is unchanged at purchase time (seats move from the seller booking to the buyer booking).
----------------------------------------------------------------------
create or replace function public.buy_resale(p_listing uuid, p_seats int)
returns jsonb language plpgsql security definer set search_path = public, app as $$
declare l record; sb record; t record; v_buyer uuid := auth.uid(); v_booking uuid;
begin
  if v_buyer is null then raise exception 'UNAUTHENTICATED' using errcode='P0001'; end if;
  select * into l from public.resale_listings where id = p_listing for update;   -- lock listing
  if l is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if l.status <> 'open' then raise exception 'RESALE_UNAVAILABLE' using errcode='P0001'; end if;
  if l.seller_id = v_buyer then raise exception 'CANNOT_BUY_OWN_RESALE' using errcode='P0001'; end if;
  if p_seats < 1 or p_seats > (l.seats_for_sale - l.seats_sold) then raise exception 'INVALID_SEATS' using errcode='P0001'; end if;

  select * into sb from public.bookings where id = l.booking_id for update;      -- lock seller booking
  if sb.status <> 'confirmed' then raise exception 'RESALE_UNAVAILABLE' using errcode='P0001'; end if;
  if sb.seats < p_seats then raise exception 'INVALID_SEATS' using errcode='P0001'; end if;
  select * into t from public.trips where id = sb.trip_id;
  if t.departure_at <= now() then raise exception 'RESALE_UNAVAILABLE' using errcode='P0001'; end if;

  -- seat ownership transfer (inventory total unchanged)
  if sb.seats = p_seats then
    update public.bookings set status='cancelled' where id = sb.id;
  else
    update public.bookings set seats = sb.seats - p_seats,
                               total_amount = (sb.seats - p_seats) * sb.price_per_seat
      where id = sb.id;
  end if;

  insert into public.bookings(client_id, trip_id, pickup_checkpoint_id, dropoff_checkpoint_id,
                              seats, price_per_seat, total_amount, status, source, approval_expires_at)
  values (v_buyer, sb.trip_id, sb.pickup_checkpoint_id, sb.dropoff_checkpoint_id,
          p_seats, l.price_per_seat, l.price_per_seat * p_seats, 'pending', 'resale',
          now() + make_interval(mins => app.setting_int('booking_approval_timeout_minutes',30)))
  returning id into v_booking;

  update public.resale_listings
     set seats_sold = l.seats_sold + p_seats,
         status = (case when l.seats_sold + p_seats >= l.seats_for_sale then 'closed' else 'open' end)::resale_status,
         closed_at = case when l.seats_sold + p_seats >= l.seats_for_sale then now() end
   where id = l.id;

  perform app.audit('buy_resale','resale_listing',l.id,
    jsonb_build_object('buyer',v_buyer,'seats',p_seats,'booking_id',v_booking));
  perform app.notify(l.seller_id,'resale_purchased','notifications.resale_purchased.title','notifications.resale_purchased.body',
    jsonb_build_object('listing_id',l.id,'seats',p_seats));
  perform app.notify(t.driver_id,'booking_request','notifications.booking_request.title','notifications.booking_request.body',
    jsonb_build_object('booking_id', v_booking, 'trip_id', sb.trip_id));

  return jsonb_build_object('booking_id', v_booking, 'amount', l.price_per_seat * p_seats,
                            'booking_mode', 'driver_approval', 'status', 'pending');
end; $$;

----------------------------------------------------------------------
-- Driver cancels a trip: affected bookings are cancelled (no payment handling).
----------------------------------------------------------------------
create or replace function public.cancel_trip(p_trip uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public, app as $$
declare v record; b record;
begin
  select * into v from public.trips where id = p_trip for update;
  if v is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if v.driver_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v.status in ('in_progress','completed','cancelled') then raise exception 'INVALID_TRIP_STATE' using errcode='P0001'; end if;

  for b in select * from public.bookings where trip_id = p_trip and status in ('pending','confirmed') for update loop
    perform app.move_seats(p_trip, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
    update public.bookings set status='cancelled', approval_expires_at=null where id = b.id;
    update public.transfer_requests set status='cancelled', responded_at=now()
      where booking_id = b.id and status='pending';
    update public.resale_listings set status='cancelled', closed_at=now()
      where booking_id = b.id and status='open';
    perform app.notify(b.client_id,'trip_cancelled','notifications.trip_cancelled.title','notifications.trip_cancelled.body',
                       jsonb_build_object('booking_id', b.id, 'trip_id', p_trip));
  end loop;

  update public.trips set status='cancelled', cancelled_at=now() where id = p_trip;
  perform app.audit('cancel_trip','trip',p_trip, jsonb_build_object('reason', p_reason));
end; $$;
