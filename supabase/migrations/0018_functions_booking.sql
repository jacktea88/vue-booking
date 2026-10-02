-- 0017_functions_booking.sql — bookings, payments, cancellation, resale, transfer, ratings, admin

----------------------------------------------------------------------
-- Booking creation (atomic seat reservation + price snapshot + payment intent)
----------------------------------------------------------------------
create or replace function public.create_booking(
  p_trip uuid, p_pickup uuid, p_dropoff uuid, p_seats int, p_source booking_source default 'direct'
) returns jsonb language plpgsql security definer set search_path = public, app as $$
declare v_client uuid := auth.uid(); t record; v_price numeric; v_booking uuid; v_payment uuid; v_status booking_status;
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

  v_status := 'pending';
  insert into public.bookings(client_id, trip_id, pickup_checkpoint_id, dropoff_checkpoint_id,
                              seats, price_per_seat, total_amount, status, source, approval_expires_at)
  values (v_client, p_trip, p_pickup, p_dropoff, p_seats, v_price, v_price * p_seats, v_status, p_source,
          case when t.booking_mode='driver_approval'
               then now() + make_interval(mins => app.setting_int('booking_approval_timeout_minutes',30)) end)
  returning id into v_booking;

  insert into public.booking_payments(booking_id, amount, currency, status, provider)
  values (v_booking, v_price * p_seats, 'DZD', 'requires_payment',
          coalesce((select value #>> '{}' from public.settings where key='payment_provider'),'mock'))
  returning id into v_payment;

  perform app.audit('create_booking','booking',v_booking,
    jsonb_build_object('trip_id',p_trip,'seats',p_seats,'total',v_price*p_seats,'source',p_source));
  perform app.notify(t.driver_id,'booking_request','notifications.booking_request.title','notifications.booking_request.body',
    jsonb_build_object('booking_id', v_booking, 'trip_id', p_trip));

  return jsonb_build_object('booking_id', v_booking, 'payment_id', v_payment,
                            'amount', v_price * p_seats, 'price_per_seat', v_price,
                            'booking_mode', t.booking_mode, 'status', v_status);
end; $$;

----------------------------------------------------------------------
-- Payment state machine. Only callable by the service role (webhook / Edge Function),
-- or by any user when the mock provider is explicitly enabled for development.
----------------------------------------------------------------------
create or replace function public.apply_payment_result(
  p_payment uuid, p_new_status payment_status, p_provider_reference text default null
) returns jsonb language plpgsql security definer set search_path = public, app as $$
declare pay record; b record; t record; v_mock boolean;
begin
  v_mock := coalesce((select (value #>> '{}')::boolean from public.settings where key='allow_mock_payments'), false);
  if auth.role() <> 'service_role' and not v_mock then
    raise exception 'FORBIDDEN' using errcode='42501';
  end if;

  select * into pay from public.booking_payments where id = p_payment for update;
  if pay is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if pay.status in ('paid','refunded','partially_refunded') and p_new_status in ('paid','authorized') then
    return jsonb_build_object('payment_status', pay.status, 'idempotent', true); -- retry-safe
  end if;

  select * into b from public.bookings where id = pay.booking_id for update;
  select * into t from public.trips where id = b.trip_id;

  update public.booking_payments
     set status = p_new_status,
         provider_reference = coalesce(p_provider_reference, provider_reference),
         paid_at = case when p_new_status = 'paid' then now() else paid_at end
   where id = p_payment;
  perform app.audit('payment_state_change','booking_payment',p_payment,
    jsonb_build_object('from',pay.status,'to',p_new_status));

  if p_new_status in ('paid','authorized') then
    if t.booking_mode = 'auto_confirm' and p_new_status = 'paid' then
      update public.bookings set status='confirmed', approval_expires_at=null where id = b.id and status='pending';
      perform app.notify(b.client_id,'booking_confirmed','notifications.booking_confirmed.title','notifications.booking_confirmed.body',
        jsonb_build_object('booking_id',b.id));
      perform app.notify(t.driver_id,'booking_confirmed','notifications.booking_confirmed.title','notifications.booking_confirmed.body',
        jsonb_build_object('booking_id',b.id));
    else
      perform app.notify(t.driver_id,'booking_request','notifications.booking_request.title','notifications.booking_request.body',
        jsonb_build_object('booking_id',b.id));
    end if;
    perform app.notify(b.client_id,'payment_success','notifications.payment_success.title','notifications.payment_success.body',
      jsonb_build_object('booking_id',b.id,'amount',pay.amount));
  elsif p_new_status in ('failed','expired') then
    if b.status = 'pending' then
      perform app.move_seats(b.trip_id, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
      update public.bookings set status='cancelled' where id = b.id;
    end if;
    perform app.notify(b.client_id,'payment_failed','notifications.payment_failed.title','notifications.payment_failed.body',
      jsonb_build_object('booking_id',b.id));
  end if;

  return jsonb_build_object('payment_status', p_new_status, 'booking_id', b.id);
end; $$;

----------------------------------------------------------------------
-- Driver approval
----------------------------------------------------------------------
create or replace function public.confirm_booking(p_booking uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare b record; t record; pay record;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id;
  if t.driver_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status <> 'pending' then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;
  if b.approval_expires_at is not null and b.approval_expires_at < now() then
    raise exception 'BOOKING_EXPIRED' using errcode='P0001'; end if;

  select * into pay from public.booking_payments where booking_id = b.id order by created_at desc limit 1 for update;
  if pay is null or pay.status not in ('authorized','paid') then
    raise exception 'PAYMENT_NOT_AUTHORIZED' using errcode='P0001'; end if;
  if pay.status = 'authorized' then  -- capture
    update public.booking_payments set status='paid', paid_at=now() where id = pay.id;
    perform app.audit('payment_state_change','booking_payment',pay.id, jsonb_build_object('from','authorized','to','paid'));
  end if;

  update public.bookings set status='confirmed', approval_expires_at=null where id = b.id;
  perform app.audit('confirm_booking','booking',b.id,'{}'::jsonb);
  perform app.notify(b.client_id,'booking_accepted','notifications.booking_accepted.title','notifications.booking_accepted.body',
    jsonb_build_object('booking_id',b.id));
end; $$;

create or replace function public.reject_booking(p_booking uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public, app as $$
declare b record; t record; pay record;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id;
  if t.driver_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status <> 'pending' then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;

  perform app.move_seats(b.trip_id, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
  update public.bookings set status='rejected' where id = b.id;

  select * into pay from public.booking_payments where booking_id = b.id order by created_at desc limit 1 for update;
  if pay is not null then
    if pay.status = 'authorized' then
      update public.booking_payments set status='expired' where id = pay.id;    -- release hold
    elsif pay.status = 'paid' then
      update public.booking_payments set status='refunded', refunded_amount = pay.amount where id = pay.id;
      perform app.audit('refund','booking_payment',pay.id, jsonb_build_object('amount',pay.amount,'reason','rejected'));
    end if;
  end if;

  perform app.audit('reject_booking','booking',b.id, jsonb_build_object('reason',p_reason));
  perform app.notify(b.client_id,'booking_rejected','notifications.booking_rejected.title','notifications.booking_rejected.body',
    jsonb_build_object('booking_id',b.id));
end; $$;

-- Expire stale driver-approval bookings (call from cron / Edge Function).
create or replace function public.expire_pending_bookings()
returns int language plpgsql security definer set search_path = public, app as $$
declare b record; n int := 0; pay record;
begin
  for b in select * from public.bookings
            where status='pending' and approval_expires_at is not null and approval_expires_at < now()
            for update loop
    perform app.move_seats(b.trip_id, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
    update public.bookings set status='rejected' where id = b.id;
    select * into pay from public.booking_payments where booking_id=b.id order by created_at desc limit 1;
    if pay is not null and pay.status = 'authorized' then
      update public.booking_payments set status='expired' where id = pay.id;
    elsif pay is not null and pay.status = 'paid' then
      update public.booking_payments set status='refunded', refunded_amount = pay.amount where id = pay.id;
    end if;
    perform app.audit('expire_booking','booking',b.id,'{}'::jsonb);
    perform app.notify(b.client_id,'booking_rejected','notifications.booking_expired.title','notifications.booking_expired.body',
      jsonb_build_object('booking_id',b.id));
    n := n + 1;
  end loop;
  return n;
end; $$;

----------------------------------------------------------------------
-- Cancellation (80% refund when eligible) / no-show (0%)
----------------------------------------------------------------------
create or replace function public.cancellation_quote(p_booking uuid)
returns jsonb language plpgsql stable security definer set search_path = public, app as $$
declare b record; t record; pay record; v_hours numeric; v_mins numeric; v_elig boolean; v_pct numeric;
begin
  select * into b from public.bookings where id = p_booking;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if b.client_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  select * into t from public.trips where id = b.trip_id;
  select * into pay from public.booking_payments where booking_id=b.id order by created_at desc limit 1;
  v_hours := app.setting_num('cancellation_window_hours',24);
  v_mins  := app.setting_num('cancellation_min_minutes_after_booking',30);
  v_pct   := app.setting_num('refund_percentage',80);
  v_elig := t.departure_at > now() + make_interval(hours => v_hours::int)
            and now() > b.created_at + make_interval(mins => v_mins::int)
            and pay.status is not null and pay.status in ('paid','authorized');
  return jsonb_build_object('eligible', v_elig, 'refund_percentage', case when v_elig then v_pct else 0 end,
    'refund_amount', case when v_elig then round(coalesce(pay.amount,0) * v_pct / 100, 2) else 0 end,
    'paid_amount', coalesce(pay.amount,0));
end; $$;

create or replace function public.cancel_booking(p_booking uuid)
returns jsonb language plpgsql security definer set search_path = public, app as $$
declare b record; t record; pay record; q jsonb; v_refund numeric := 0;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if b.client_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status not in ('pending','confirmed') then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id for update;

  q := public.cancellation_quote(p_booking);
  select * into pay from public.booking_payments where booking_id=b.id order by created_at desc limit 1 for update;

  perform app.move_seats(b.trip_id, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
  update public.bookings set status='cancelled' where id = b.id;
  update public.transfer_requests set status='cancelled', responded_at=now() where booking_id=b.id and status='pending';
  update public.resale_listings set status='cancelled', closed_at=now() where booking_id=b.id and status='open';

  if pay is not null then
    if (q->>'eligible')::boolean then
      v_refund := (q->>'refund_amount')::numeric;
      update public.booking_payments
        set status = (case when v_refund >= pay.amount then 'refunded' else 'partially_refunded' end)::payment_status,
            refunded_amount = least(v_refund, pay.amount)
      where id = pay.id;
      perform app.audit('refund','booking_payment',pay.id, jsonb_build_object('amount',v_refund,'reason','client_cancellation'));
      perform app.notify(b.client_id,'refund','notifications.refund.title','notifications.refund.body',
        jsonb_build_object('booking_id',b.id,'amount',v_refund));
    elsif pay.status = 'authorized' then
      update public.booking_payments set status='expired' where id = pay.id;
    end if;
  end if;

  perform app.audit('cancel_booking','booking',b.id, q);
  perform app.notify(t.driver_id,'booking_cancelled','notifications.booking_cancelled.title','notifications.booking_cancelled.body',
    jsonb_build_object('booking_id',b.id));
  return jsonb_build_object('cancelled', true, 'refund_amount', v_refund);
end; $$;

create or replace function public.mark_no_show(p_booking uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare b record; t record;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id;
  if t.driver_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status <> 'confirmed' then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;
  update public.bookings set status='no_show' where id = b.id;   -- 0% refund by policy
  perform app.audit('mark_no_show','booking',b.id, jsonb_build_object('refund',0));
end; $$;

----------------------------------------------------------------------
-- Resale
----------------------------------------------------------------------
create or replace function public.create_resale(p_booking uuid, p_seats int, p_price numeric)
returns uuid language plpgsql security definer set search_path = public, app as $$
declare b record; t record; v_id uuid; v_sold int;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if b.client_id <> auth.uid() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status <> 'confirmed' then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id;
  if t.departure_at <= now() or t.status not in ('published','boarding') then
    raise exception 'RESALE_UNAVAILABLE' using errcode='P0001'; end if;
  if exists (select 1 from public.transfer_requests where booking_id = b.id and status='pending') then
    raise exception 'TRANSFER_IN_PROGRESS' using errcode='P0001'; end if;
  if exists (select 1 from public.resale_listings where booking_id = b.id and status='open') then
    raise exception 'RESALE_ALREADY_OPEN' using errcode='P0001'; end if;
  if p_price > b.price_per_seat then raise exception 'RESALE_PRICE_TOO_HIGH' using errcode='P0001'; end if;
  if p_price < 0 then raise exception 'INVALID_PRICE' using errcode='P0001'; end if;

  select coalesce(sum(seats_sold),0) into v_sold from public.resale_listings where booking_id = b.id;
  if p_seats < 1 or p_seats > (b.seats - v_sold) then raise exception 'INVALID_SEATS' using errcode='P0001'; end if;

  insert into public.resale_listings(booking_id, seller_id, seats_for_sale, price_per_seat)
  values (b.id, b.client_id, p_seats, p_price) returning id into v_id;
  perform app.audit('create_resale','resale_listing',v_id, jsonb_build_object('seats',p_seats,'price',p_price));
  perform app.notify(b.client_id,'resale_created','notifications.resale_created.title','notifications.resale_created.body',
    jsonb_build_object('listing_id',v_id));
  return v_id;
end; $$;

create or replace function public.cancel_resale(p_listing uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare l record;
begin
  select * into l from public.resale_listings where id = p_listing for update;
  if l is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if l.seller_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if l.status <> 'open' then raise exception 'RESALE_UNAVAILABLE' using errcode='P0001'; end if;
  update public.resale_listings set status='cancelled', closed_at=now() where id = p_listing;
  perform app.audit('cancel_resale','resale_listing',p_listing,'{}'::jsonb);
end; $$;

-- Buyer purchases N seats: seats move from the seller's booking to a new buyer booking.
-- No extra seats are created on the trip, so no re-reservation is needed.
create or replace function public.buy_resale(p_listing uuid, p_seats int)
returns jsonb language plpgsql security definer set search_path = public, app as $$
declare l record; sb record; t record; v_buyer uuid := auth.uid(); v_booking uuid; v_payment uuid;
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
                              seats, price_per_seat, total_amount, status, source)
  values (v_buyer, sb.trip_id, sb.pickup_checkpoint_id, sb.dropoff_checkpoint_id,
          p_seats, l.price_per_seat, l.price_per_seat * p_seats, 'pending', 'resale')
  returning id into v_booking;

  insert into public.booking_payments(booking_id, amount, currency, status, provider)
  values (v_booking, l.price_per_seat * p_seats, 'DZD', 'requires_payment',
          coalesce((select value #>> '{}' from public.settings where key='payment_provider'),'mock'))
  returning id into v_payment;

  update public.resale_listings
     set seats_sold = l.seats_sold + p_seats,
         status = (case when l.seats_sold + p_seats >= l.seats_for_sale then 'closed' else 'open' end)::resale_status,
         closed_at = case when l.seats_sold + p_seats >= l.seats_for_sale then now() end
   where id = l.id;

  perform app.audit('buy_resale','resale_listing',l.id,
    jsonb_build_object('buyer',v_buyer,'seats',p_seats,'booking_id',v_booking));
  perform app.notify(l.seller_id,'resale_purchased','notifications.resale_purchased.title','notifications.resale_purchased.body',
    jsonb_build_object('listing_id',l.id,'seats',p_seats));

  return jsonb_build_object('booking_id', v_booking, 'payment_id', v_payment,
                            'amount', l.price_per_seat * p_seats, 'booking_mode', t.booking_mode);
end; $$;

----------------------------------------------------------------------
-- Transfer (booking-level, driver initiated, client approved)
----------------------------------------------------------------------
create or replace function public.find_compatible_trips(p_booking uuid, p_limit int default 20)
returns table (trip_id uuid, departure_at timestamptz, driver_name text,
               pickup_checkpoint_id uuid, pickup_name text,
               dropoff_checkpoint_id uuid, dropoff_name text, available_seats int)
language sql stable security definer set search_path = public, app as $$
  with b as (select * from public.bookings where id = p_booking),
       pu as (select location from public.trip_checkpoints where id = (select pickup_checkpoint_id from b)),
       dr as (select location from public.trip_checkpoints where id = (select dropoff_checkpoint_id from b)),
       tol as (select app.setting_int('search_tolerance_meters',15000)::float8 m)
  select distinct on (t.id) t.id, t.departure_at, pr.full_name,
         a.id, a.name, c.id, c.name,
         (select min(g.capacity - g.reserved_seats)::int from public.trip_segments g
           where g.id in (select segment_id from app.covered_segment_ids(t.id, a.id, c.id)))
  from public.trips t
  join public.trip_checkpoints a on a.trip_id = t.id
  join public.trip_checkpoints c on c.trip_id = t.id
  join public.public_profiles pr on pr.id = t.driver_id
  cross join tol
  where t.status='published' and t.id <> (select trip_id from b)
    and t.departure_at > now()
    and a.sequence < c.sequence
    and st_dwithin(a.location, (select location from pu), tol.m)
    and st_dwithin(c.location, (select location from dr), tol.m)
    and (select min(g.capacity - g.reserved_seats) from public.trip_segments g
          where g.id in (select segment_id from app.covered_segment_ids(t.id, a.id, c.id))) >= (select seats from b)
  order by t.id, t.departure_at
  limit greatest(p_limit,1);
$$;

create or replace function public.request_transfer(p_booking uuid, p_to_trip uuid, p_to_pickup uuid, p_to_dropoff uuid)
returns uuid language plpgsql security definer set search_path = public, app as $$
declare b record; t record; tt record; v_id uuid;
begin
  select * into b from public.bookings where id = p_booking for update;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id;
  if t.driver_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status <> 'confirmed' then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;
  if exists (select 1 from public.transfer_requests where booking_id=b.id and status='pending') then
    raise exception 'TRANSFER_ALREADY_PENDING' using errcode='P0001'; end if;
  if exists (select 1 from public.resale_listings where booking_id=b.id and status='open') then
    raise exception 'RESALE_IN_PROGRESS' using errcode='P0001'; end if;

  select * into tt from public.trips where id = p_to_trip;
  if tt is null or tt.status <> 'published' or tt.departure_at <= now() then
    raise exception 'TRANSFER_UNAVAILABLE' using errcode='P0001'; end if;
  -- validates direction + existence on the target trip
  perform app.covered_segment_ids(p_to_trip, p_to_pickup, p_to_dropoff);

  insert into public.transfer_requests(booking_id, from_trip_id, to_trip_id, to_pickup_checkpoint_id,
                                       to_dropoff_checkpoint_id, requested_by)
  values (b.id, b.trip_id, p_to_trip, p_to_pickup, p_to_dropoff, auth.uid())
  returning id into v_id;

  perform app.audit('request_transfer','transfer_request',v_id, jsonb_build_object('booking_id',b.id,'to_trip',p_to_trip));
  perform app.notify(b.client_id,'transfer_request','notifications.transfer_request.title','notifications.transfer_request.body',
    jsonb_build_object('transfer_id',v_id,'booking_id',b.id));
  return v_id;
end; $$;

create or replace function public.approve_transfer(p_transfer uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare tr record; b record;
begin
  select * into tr from public.transfer_requests where id = p_transfer for update;
  if tr is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if tr.status <> 'pending' then raise exception 'TRANSFER_UNAVAILABLE' using errcode='P0001'; end if;
  select * into b from public.bookings where id = tr.booking_id for update;
  if b.client_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if b.status <> 'confirmed' then raise exception 'INVALID_BOOKING_STATE' using errcode='P0001'; end if;

  -- reserve on target first (fails => nothing changes), then release on source
  perform app.move_seats(tr.to_trip_id, tr.to_pickup_checkpoint_id, tr.to_dropoff_checkpoint_id, b.seats);
  perform app.move_seats(b.trip_id, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);

  -- booking identity + financial snapshot are preserved
  update public.bookings
     set trip_id = tr.to_trip_id,
         pickup_checkpoint_id = tr.to_pickup_checkpoint_id,
         dropoff_checkpoint_id = tr.to_dropoff_checkpoint_id
   where id = b.id;

  update public.transfer_requests set status='approved', responded_at=now() where id = p_transfer;
  perform app.audit('approve_transfer','transfer_request',p_transfer,
    jsonb_build_object('booking_id',b.id,'from_trip',tr.from_trip_id,'to_trip',tr.to_trip_id,'price_per_seat',b.price_per_seat));
  perform app.notify(tr.requested_by,'transfer_accepted','notifications.transfer_accepted.title','notifications.transfer_accepted.body',
    jsonb_build_object('transfer_id',p_transfer));
end; $$;

create or replace function public.reject_transfer(p_transfer uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare tr record; b record;
begin
  select * into tr from public.transfer_requests where id = p_transfer for update;
  if tr is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if tr.status <> 'pending' then raise exception 'TRANSFER_UNAVAILABLE' using errcode='P0001'; end if;
  select * into b from public.bookings where id = tr.booking_id;
  if b.client_id <> auth.uid() and tr.requested_by <> auth.uid() and not app.is_admin() then
    raise exception 'FORBIDDEN' using errcode='42501'; end if;
  update public.transfer_requests
     set status = (case when tr.requested_by = auth.uid() then 'cancelled' else 'rejected' end)::transfer_status,
         responded_at = now()
   where id = p_transfer;
  perform app.audit('reject_transfer','transfer_request',p_transfer,'{}'::jsonb);
  perform app.notify(tr.requested_by,'transfer_rejected','notifications.transfer_rejected.title','notifications.transfer_rejected.body',
    jsonb_build_object('transfer_id',p_transfer));
end; $$;

----------------------------------------------------------------------
-- Ratings
----------------------------------------------------------------------
create or replace function public.rate_booking(p_booking uuid, p_rating int, p_comment text default null)
returns uuid language plpgsql security definer set search_path = public, app as $$
declare b record; t record; v_to uuid; v_id uuid;
begin
  if p_rating < 1 or p_rating > 5 then raise exception 'INVALID_RATING' using errcode='P0001'; end if;
  select * into b from public.bookings where id = p_booking;
  if b is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  select * into t from public.trips where id = b.trip_id;
  if b.status <> 'completed' then raise exception 'BOOKING_NOT_COMPLETED' using errcode='P0001'; end if;
  if auth.uid() = b.client_id then v_to := t.driver_id;
  elsif auth.uid() = t.driver_id then v_to := b.client_id;
  else raise exception 'FORBIDDEN' using errcode='42501'; end if;

  insert into public.ratings(booking_id, from_user_id, to_user_id, rating, comment)
  values (p_booking, auth.uid(), v_to, p_rating, p_comment)
  returning id into v_id;
  return v_id;
end; $$;

----------------------------------------------------------------------
-- Verification / admin
----------------------------------------------------------------------
create or replace function public.submit_verification_document(p_type document_type, p_path text)
returns uuid language plpgsql security definer set search_path = public, app as $$
declare v_id uuid;
begin
  if auth.uid() is null then raise exception 'UNAUTHENTICATED' using errcode='P0001'; end if;
  insert into public.verification_documents(user_id, type, storage_path, status)
  values (auth.uid(), p_type, p_path, 'pending') returning id into v_id;
  update public.profiles set identity_status='pending'
    where id = auth.uid() and p_type='identity_card' and identity_status='rejected';
  return v_id;
end; $$;

create or replace function public.review_document(p_doc uuid, p_status document_status, p_reason text default null)
returns void language plpgsql security definer set search_path = public, app as $$
declare d record; v_required int; v_ok int;
begin
  if not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  select * into d from public.verification_documents where id = p_doc for update;
  if d is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  update public.verification_documents
    set status=p_status, rejection_reason=p_reason, reviewed_by=auth.uid(), reviewed_at=now()
    where id = p_doc;

  if d.type = 'identity_card' then
    update public.profiles set identity_status = (case p_status when 'verified' then 'verified'
      when 'rejected' then 'rejected' else 'pending' end)::identity_status where id = d.user_id;
  end if;

  -- driver becomes verified once all four required documents are verified
  if exists (select 1 from public.profiles where id = d.user_id and role='driver') then
    select count(*) into v_ok from public.verification_documents
      where user_id = d.user_id and status='verified'
        and type in ('identity_card','driving_license','vehicle_registration','insurance')
        and id in (select distinct on (type) id from public.verification_documents
                   where user_id = d.user_id and status='verified' order by type, created_at desc);
    update public.driver_profiles
      set overall_verified = (v_ok >= 4), verified_at = case when v_ok >= 4 then now() end
      where id = d.user_id;
  end if;

  perform app.audit(case p_status when 'rejected' then 'document_rejection' else 'identity_verification' end,
                    'verification_document', p_doc, jsonb_build_object('status',p_status,'reason',p_reason));
  perform app.notify(d.user_id,
    case p_status when 'rejected' then 'document_rejection' else 'identity_verification' end,
    'notifications.document_review.title','notifications.document_review.body',
    jsonb_build_object('document_id',p_doc,'status',p_status,'reason',p_reason));
end; $$;

create or replace function public.admin_set_role(p_user uuid, p_role user_role)
returns void language plpgsql security definer set search_path = public, app as $$
begin
  if not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  update public.profiles set role = p_role where id = p_user;
  if p_role = 'driver' then insert into public.driver_profiles(id) values (p_user) on conflict do nothing; end if;
  perform app.audit('admin_set_role','profile',p_user, jsonb_build_object('role',p_role));
end; $$;

create or replace function public.admin_set_setting(p_key text, p_value jsonb)
returns void language plpgsql security definer set search_path = public, app as $$
begin
  if not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  insert into public.settings(key,value,updated_by,updated_at) values (p_key,p_value,auth.uid(),now())
  on conflict (key) do update set value=excluded.value, updated_by=excluded.updated_by, updated_at=now();
  perform app.audit('admin_override','settings',null, jsonb_build_object('key',p_key,'value',p_value));
end; $$;

create or replace function public.admin_stats()
returns jsonb language sql stable security definer set search_path = public, app as $$
  select case when not app.is_admin() then jsonb_build_object('error','FORBIDDEN') else jsonb_build_object(
    'pending_verifications', (select count(*) from public.verification_documents where status='pending'),
    'active_trips', (select count(*) from public.trips where status in ('boarding','in_progress')),
    'upcoming_trips', (select count(*) from public.trips where status='published' and departure_at > now()),
    'bookings_today', (select count(*) from public.bookings where created_at >= current_date),
    'paid_amount_today', (select coalesce(sum(amount),0) from public.booking_payments where status='paid' and paid_at >= current_date),
    'refunded_amount_today', (select coalesce(sum(refunded_amount),0) from public.booking_payments where updated_at >= current_date),
    'pending_transfers', (select count(*) from public.transfer_requests where status='pending'),
    'open_resales', (select count(*) from public.resale_listings where status='open')
  ) end;
$$;

-- Trip detail bundle for the client UI (one round-trip instead of N queries).
create or replace function public.get_trip_details(p_trip uuid)
returns jsonb language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object(
    'trip', to_jsonb(t) - 'driver_id',
    'driver', (select to_jsonb(p) from public.public_profiles p where p.id = t.driver_id),
    'vehicle', (select jsonb_build_object('brand',v.brand,'model',v.model,'color',v.color,'capacity',v.capacity)
                 from public.vehicles v where v.id = t.vehicle_id),
    'checkpoints', (select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'sequence',c.sequence,
                      'estimated_arrival',c.estimated_arrival,
                      'lat', st_y(c.location::geometry), 'lng', st_x(c.location::geometry)) order by c.sequence),'[]'::jsonb)
                    from public.trip_checkpoints c where c.trip_id = t.id),
    'segments', (select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'sequence',g.sequence,
                      'from_checkpoint_id',g.from_checkpoint_id,'to_checkpoint_id',g.to_checkpoint_id,
                      'distance_km',g.distance_km,'estimated_minutes',g.estimated_minutes,
                      'reference_price',g.reference_price,'driver_price',g.driver_price,
                      'capacity',g.capacity,'reserved_seats',g.reserved_seats) order by g.sequence),'[]'::jsonb)
                 from public.trip_segments g where g.trip_id = t.id)
  ) from public.trips t where t.id = p_trip
    and (t.status <> 'draft' or t.driver_id = auth.uid() or app.is_admin());
$$;

-- Price quote for a pickup→dropoff selection (never computed on the client).
create or replace function public.quote_booking(p_trip uuid, p_pickup uuid, p_dropoff uuid, p_seats int)
returns jsonb language sql stable security definer set search_path = public, app as $$
  select jsonb_build_object(
    'price_per_seat', app.segment_price_sum(p_trip,p_pickup,p_dropoff),
    'total_amount', app.segment_price_sum(p_trip,p_pickup,p_dropoff) * greatest(p_seats,1),
    'available_seats', (select min(g.capacity - g.reserved_seats) from public.trip_segments g
                        where g.id in (select segment_id from app.covered_segment_ids(p_trip,p_pickup,p_dropoff))),
    'currency','DZD');
$$;

revoke all on function public.apply_payment_result(uuid,payment_status,text) from public;
grant execute on function public.apply_payment_result(uuid,payment_status,text) to authenticated, service_role;
