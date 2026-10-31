-- tests/sql/business_rules.test.sql
-- Integration tests for RLS + critical RPCs. Run against a local Supabase stack:
--   supabase db reset && psql "$SUPABASE_DB_URL" -f supabase/seed_dev.sql \
--     && psql "$SUPABASE_DB_URL" -f tests/sql/business_rules.test.sql
-- Each block raises an exception on failure, so a clean run = all tests pass.

\set ON_ERROR_STOP on
begin;

do $$
declare v_driver uuid; v_client uuid; v_client2 uuid; v_admin uuid; v_trip uuid;
        cp0 uuid; cp1 uuid; cp2 uuid; cp3 uuid; v_res jsonb; v_booking uuid;
        v_listing uuid; v_transfer uuid; v_trip2 uuid; v_seats int; v_price numeric; v_rows int;
begin
  select id into v_driver from auth.users where email='driver@demo.test';
  select id into v_client from auth.users where email='client@demo.test';
  select id into v_client2 from auth.users where email='client2@demo.test';
  select id into v_admin  from auth.users where email='admin@demo.test';
  select id into v_trip from public.trips where driver_id = v_driver order by created_at limit 1;
  select id into cp0 from public.trip_checkpoints where trip_id=v_trip and sequence=0;
  select id into cp1 from public.trip_checkpoints where trip_id=v_trip and sequence=1;
  select id into cp3 from public.trip_checkpoints where trip_id=v_trip and sequence=3;

  ---------------------------------------------------------------- pricing
  if app.segment_price_sum(v_trip, cp0, cp3) <>
     (select sum(driver_price) from public.trip_segments where trip_id=v_trip) then
    raise exception 'FAIL: multi-segment price must equal the sum of segment prices';
  end if;

  ---------------------------------------------------------------- direction
  begin
    perform app.covered_segment_ids(v_trip, cp3, cp0);
    raise exception 'FAIL: reversed route must be rejected';
  exception when others then
    if sqlerrm <> 'INVALID_ROUTE_DIRECTION' then raise; end if;
  end;

  ---------------------------------------------------------------- booking + atomic seats
  perform set_config('request.jwt.claim.sub', v_client::text, true);
  perform set_config('role','authenticated', true);
  v_res := public.create_booking(v_trip, cp0, cp3, 2);
  v_booking := (v_res->>'booking_id')::uuid;
  if v_res ? 'payment_id' then
    raise exception 'FAIL: create_booking must not return a payment';
  end if;

  if (select min(reserved_seats) from public.trip_segments where trip_id=v_trip) <> 2 then
    raise exception 'FAIL: seats must be reserved on EVERY covered segment';
  end if;

  ---------------------------------------------------------------- overbooking prevention
  begin
    perform public.create_booking(v_trip, cp0, cp1, 5);
    raise exception 'FAIL: overbooking must be rejected';
  exception when others then
    if sqlerrm <> 'NO_SEATS_AVAILABLE' then raise; end if;
  end;

  ---------------------------------------------------------------- approval-only: auto confirm without payment
  if (select status from public.bookings where id=v_booking) <> 'confirmed' then
    raise exception 'FAIL: auto_confirm booking must be confirmed immediately (no payment step)';
  end if;
  if exists (select 1 from public.booking_payments where booking_id = v_booking) then
    raise exception 'FAIL: no payment row must be created in the approval-only flow';
  end if;

  ---------------------------------------------------------------- price immutability
  -- Layer 1 (RLS): a normal authenticated client has no UPDATE policy on bookings,
  -- so the write is filtered out entirely and touches zero rows.
  update public.bookings set price_per_seat = 1 where id = v_booking;
  get diagnostics v_rows = row_count;
  if v_rows <> 0 then
    raise exception 'FAIL: a client must not be able to update a booking row directly';
  end if;

  -- Layer 2 (trigger): even a privileged role cannot change a confirmed price.
  perform set_config('role', 'postgres', true);
  begin
    update public.bookings set price_per_seat = 1 where id = v_booking;
    raise exception 'FAIL: confirmed booking price must be immutable';
  exception when others then
    if sqlerrm <> 'BOOKING_PRICE_IMMUTABLE' then raise; end if;
  end;
  perform set_config('role', 'authenticated', true);

  ---------------------------------------------------------------- resale: price ceiling
  select price_per_seat into v_price from public.bookings where id=v_booking;
  begin
    perform public.create_resale(v_booking, 1, v_price + 100);
    raise exception 'FAIL: resale price above original must be rejected';
  exception when others then
    if sqlerrm <> 'RESALE_PRICE_TOO_HIGH' then raise; end if;
  end;

  ---------------------------------------------------------------- resale: partial sale + closure
  v_listing := public.create_resale(v_booking, 1, v_price - 100);
  perform set_config('request.jwt.claim.sub', v_client2::text, true);
  perform public.buy_resale(v_listing, 1);
  if (select status from public.resale_listings where id=v_listing) <> 'closed' then
    raise exception 'FAIL: listing must close once all offered seats are sold';
  end if;
  if (select seats from public.bookings where id=v_booking) <> 1 then
    raise exception 'FAIL: sold seats must leave the seller booking';
  end if;
  if (select min(reserved_seats) from public.trip_segments where trip_id=v_trip) <> 2 then
    raise exception 'FAIL: resale must not create or destroy seat inventory';
  end if;

  ---------------------------------------------------------------- cancellation window (no refund)
  perform set_config('request.jwt.claim.sub', v_client::text, true);
  v_res := public.cancellation_quote(v_booking);
  if (v_res->>'eligible')::boolean is not true then
    raise exception 'FAIL: cancellation more than 24h before departure must be allowed';
  end if;

  ---------------------------------------------------------------- transfer
  -- Driver builds a second compatible trip through the real create_trip RPC.
  perform set_config('request.jwt.claim.sub', v_driver::text, true);
  v_trip2 := public.create_trip(now() + interval '4 days', 'auto_confirm', jsonb_build_array(
    jsonb_build_object('name','Alger Centre','lat',36.7538,'lng',3.0588),
    jsonb_build_object('name','Médéa','lat',36.2675,'lng',2.7539),
    jsonb_build_object('name','Laghouat','lat',33.8000,'lng',2.8650)));
  if (select count(*) from public.trip_segments where trip_id = v_trip2) <> 2 then
    raise exception 'FAIL: create_trip must derive adjacent segments automatically';
  end if;
  if (select count(*) from public.trip_segments where trip_id = v_trip2 and reference_price > 0) <> 2 then
    raise exception 'FAIL: create_trip must compute reference prices';
  end if;
  perform public.publish_trip(v_trip2);

  if (select count(*) from public.find_compatible_trips(v_booking)) < 1 then
    raise exception 'FAIL: a compatible trip must be found for transfer';
  end if;
  select trip_id, pickup_checkpoint_id, dropoff_checkpoint_id
    into v_trip2, cp0, cp3 from public.find_compatible_trips(v_booking) limit 1;

  v_price := (select price_per_seat from public.bookings where id = v_booking);
  v_transfer := public.request_transfer(v_booking, v_trip2, cp0, cp3);

  -- resale must be blocked while a transfer is pending
  perform set_config('request.jwt.claim.sub', v_client::text, true);
  begin
    perform public.create_resale(v_booking, 1, 100);
    raise exception 'FAIL: resale must be blocked while a transfer is pending';
  exception when others then
    if sqlerrm <> 'TRANSFER_IN_PROGRESS' then raise; end if;
  end;

  perform public.approve_transfer(v_transfer);
  if (select trip_id from public.bookings where id = v_booking) <> v_trip2 then
    raise exception 'FAIL: approved transfer must move the booking to the target trip';
  end if;
  if (select price_per_seat from public.bookings where id = v_booking) <> v_price then
    raise exception 'FAIL: transfer must preserve the booking price';
  end if;
  if (select min(reserved_seats) from public.trip_segments where trip_id = v_trip2) < 1 then
    raise exception 'FAIL: transfer must reserve seats on the target trip';
  end if;

  ---------------------------------------------------------------- ratings
  perform set_config('request.jwt.claim.sub', v_driver::text, true);
  perform public.start_trip(v_trip2);
  perform public.complete_trip(v_trip2);
  if (select status from public.bookings where id = v_booking) <> 'completed' then
    raise exception 'FAIL: completing a trip must complete its confirmed bookings';
  end if;
  perform public.rate_booking(v_booking, 5, 'driver rates passenger');

  perform set_config('request.jwt.claim.sub', v_client::text, true);
  perform public.rate_booking(v_booking, 4, 'passenger rates driver');
  if (select rating_count from public.profiles where id = v_driver) < 1 then
    raise exception 'FAIL: ratings must update the profile aggregate';
  end if;
  begin
    perform public.rate_booking(v_booking, 3, 'duplicate');
    raise exception 'FAIL: a user must not rate the same booking twice';
  exception when others then
    if sqlerrm not like '%duplicate key%' and sqlerrm <> 'FORBIDDEN' then raise; end if;
  end;

  ---------------------------------------------------------------- audit trail + RLS
  -- A client must not see the audit log at all (admin-only policy).
  if (select count(*) from public.audit_logs) <> 0 then
    raise exception 'FAIL: audit_logs must be invisible to non-admins';
  end if;

  -- The same query as an admin must expose the audited sensitive actions.
  perform set_config('request.jwt.claim.sub', v_admin::text, true);
  if (select count(*) from public.audit_logs where action in
      ('create_booking','approve_transfer','buy_resale')) < 3 then
    raise exception 'FAIL: sensitive actions must be audited';
  end if;

  raise notice 'ALL BUSINESS RULE TESTS PASSED';
end $$;

rollback;
