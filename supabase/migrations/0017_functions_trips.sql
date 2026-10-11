-- 0016_functions.sql — domain RPC layer. All critical operations are transactional + row-locking.
-- Error codes are stable machine-readable strings consumed by the typed frontend error mapper.

----------------------------------------------------------------------
-- Pricing / geo helpers
----------------------------------------------------------------------
create or replace function app.reference_price(p_distance_km numeric)
returns numeric language plpgsql stable security definer set search_path = public, app as $$
declare v_base numeric; v_km numeric; v_round numeric; v_p numeric;
begin
  v_base := app.setting_num('price_base_dzd', 50);
  v_km   := app.setting_num('price_per_km_dzd', 8);
  v_round:= greatest(app.setting_num('price_rounding_dzd', 50), 1);
  v_p := v_base + (v_km * p_distance_km);
  return round(v_p / v_round) * v_round;
end; $$;

create or replace function app.assert_driver_verified(p_driver uuid)
returns void language plpgsql stable security definer set search_path = public, app as $$
begin
  if not exists (select 1 from public.driver_profiles d
                 join public.profiles p on p.id = d.id
                 where d.id = p_driver and d.overall_verified and p.identity_status = 'verified' and p.role = 'driver') then
    raise exception 'DRIVER_NOT_VERIFIED' using errcode = 'P0001';
  end if;
end; $$;

-- Segment indexes covered by a pickup→dropoff ride.
create or replace function app.covered_segment_ids(p_trip uuid, p_pickup uuid, p_dropoff uuid)
returns table (segment_id uuid) language plpgsql stable security definer set search_path = public, app as $$
declare s_from int; s_to int;
begin
  -- NB: the OUT column is named segment_id (not id) so it cannot shadow
  -- trip_checkpoints.id / trip_segments.id inside the queries below.
  select c.sequence into s_from from public.trip_checkpoints c where c.id = p_pickup and c.trip_id = p_trip;
  select c.sequence into s_to   from public.trip_checkpoints c where c.id = p_dropoff and c.trip_id = p_trip;
  if s_from is null or s_to is null then raise exception 'INVALID_CHECKPOINT' using errcode='P0001'; end if;
  if s_from >= s_to then raise exception 'INVALID_ROUTE_DIRECTION' using errcode='P0001'; end if;
  return query
    select g.id from public.trip_segments g
    join public.trip_checkpoints c on c.id = g.from_checkpoint_id
    where g.trip_id = p_trip and c.sequence >= s_from and c.sequence < s_to;
end; $$;

create or replace function app.segment_price_sum(p_trip uuid, p_pickup uuid, p_dropoff uuid)
returns numeric language sql stable security definer set search_path = public, app as $$
  select coalesce(sum(g.driver_price),0) from public.trip_segments g
  where g.id in (select segment_id from app.covered_segment_ids(p_trip, p_pickup, p_dropoff));
$$;

-- Lock + reserve (delta > 0) or release (delta < 0) seats on every covered segment.
create or replace function app.move_seats(p_trip uuid, p_pickup uuid, p_dropoff uuid, p_delta int)
returns void language plpgsql security definer set search_path = public, app as $$
declare r record;
begin
  for r in
    select g.id, g.capacity, g.reserved_seats from public.trip_segments g
    where g.id in (select segment_id from app.covered_segment_ids(p_trip, p_pickup, p_dropoff))
    order by g.sequence
    for update
  loop
    if p_delta > 0 and r.reserved_seats + p_delta > r.capacity then
      raise exception 'NO_SEATS_AVAILABLE' using errcode = 'P0001';
    end if;
    update public.trip_segments
      set reserved_seats = greatest(reserved_seats + p_delta, 0)
      where id = r.id;
  end loop;
end; $$;

----------------------------------------------------------------------
-- Trips
----------------------------------------------------------------------
-- p_checkpoints: [{"name":"Alger","lat":36.75,"lng":3.06,"place_id":null}, ...] ordered
create or replace function public.create_trip(
  p_departure_at timestamptz,
  p_booking_mode booking_mode,
  p_checkpoints jsonb
) returns uuid language plpgsql security definer set search_path = public, app as $$
declare v_driver uuid := auth.uid();
        v_vehicle record; v_trip uuid; i int; n int;
        v_prev_id uuid; v_prev_loc geography; v_cur_id uuid; v_cur_loc geography;
        v_dist numeric; v_min int; v_speed numeric; v_elapsed numeric := 0; v_seq int := 0;
        cp jsonb;
begin
  if v_driver is null then raise exception 'UNAUTHENTICATED' using errcode='P0001'; end if;
  perform app.assert_driver_verified(v_driver);
  select * into v_vehicle from public.vehicles where driver_id = v_driver;
  if v_vehicle is null then raise exception 'VEHICLE_REQUIRED' using errcode='P0001'; end if;
  n := jsonb_array_length(coalesce(p_checkpoints,'[]'::jsonb));
  if n < 2 then raise exception 'AT_LEAST_TWO_CHECKPOINTS' using errcode='P0001'; end if;
  if p_departure_at <= now() then raise exception 'DEPARTURE_IN_PAST' using errcode='P0001'; end if;

  insert into public.trips(driver_id, vehicle_id, departure_at, booking_mode, status)
  values (v_driver, v_vehicle.id, p_departure_at, p_booking_mode, 'draft')
  returning id into v_trip;

  v_speed := greatest(app.setting_num('average_speed_kmh', 70), 1);

  for i in 0..n-1 loop
    cp := p_checkpoints->i;
    v_cur_loc := st_setsrid(st_makepoint((cp->>'lng')::float8, (cp->>'lat')::float8),4326)::geography;
    insert into public.trip_checkpoints(trip_id, place_id, name, location, sequence, estimated_arrival)
    values (v_trip, nullif(cp->>'place_id','')::uuid, cp->>'name', v_cur_loc, i,
            p_departure_at + make_interval(mins => 0))
    returning id into v_cur_id;

    if i > 0 then
      v_dist := round((st_distance(v_prev_loc, v_cur_loc) / 1000.0)::numeric, 2);
      v_min := greatest(ceil((v_dist / v_speed) * 60)::int, 1);
      v_elapsed := v_elapsed + v_min;
      update public.trip_checkpoints set estimated_arrival = p_departure_at + make_interval(mins => v_elapsed::int)
        where id = v_cur_id;
      insert into public.trip_segments(trip_id, from_checkpoint_id, to_checkpoint_id, sequence,
                                       distance_km, estimated_minutes, reference_price, driver_price, capacity)
      values (v_trip, v_prev_id, v_cur_id, v_seq, v_dist, v_min,
              app.reference_price(v_dist), app.reference_price(v_dist), v_vehicle.capacity);
      v_seq := v_seq + 1;
    end if;
    v_prev_id := v_cur_id; v_prev_loc := v_cur_loc;
  end loop;

  perform app.audit('create_trip','trip',v_trip, jsonb_build_object('checkpoints', n));
  return v_trip;
end; $$;

create or replace function public.set_segment_price(p_segment uuid, p_price numeric)
returns void language plpgsql security definer set search_path = public, app as $$
declare v record;
begin
  select g.*, t.driver_id, t.status into v from public.trip_segments g join public.trips t on t.id = g.trip_id
   where g.id = p_segment;
  if v is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if v.driver_id <> auth.uid() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v.status <> 'draft' then raise exception 'TRIP_ALREADY_PUBLISHED' using errcode='P0001'; end if;
  if p_price < 0 then raise exception 'INVALID_PRICE' using errcode='P0001'; end if;
  update public.trip_segments set driver_price = p_price where id = p_segment;
end; $$;

create or replace function public.publish_trip(p_trip uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare v record;
begin
  select * into v from public.trips where id = p_trip for update;
  if v is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if v.driver_id <> auth.uid() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  perform app.assert_driver_verified(v.driver_id);
  if v.status <> 'draft' then raise exception 'TRIP_ALREADY_PUBLISHED' using errcode='P0001'; end if;
  if (select count(*) from public.trip_checkpoints where trip_id = p_trip) < 2 then
    raise exception 'AT_LEAST_TWO_CHECKPOINTS' using errcode='P0001'; end if;
  update public.trips set status='published', published_at = now() where id = p_trip;
  perform app.audit('publish_trip','trip',p_trip,'{}'::jsonb);
end; $$;

create or replace function public.start_trip(p_trip uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare v record; b record;
begin
  select * into v from public.trips where id = p_trip for update;
  if v is null or v.driver_id <> auth.uid() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v.status not in ('published','boarding') then raise exception 'INVALID_TRIP_STATE' using errcode='P0001'; end if;
  update public.trips set status='in_progress', started_at=now() where id = p_trip;
  for b in select * from public.bookings where trip_id = p_trip and status='confirmed' loop
    perform app.notify(b.client_id,'trip_started','notifications.trip_started.title','notifications.trip_started.body',
                       jsonb_build_object('booking_id', b.id, 'trip_id', p_trip));
  end loop;
  perform app.audit('start_trip','trip',p_trip,'{}'::jsonb);
end; $$;

create or replace function public.complete_trip(p_trip uuid)
returns void language plpgsql security definer set search_path = public, app as $$
declare v record; b record;
begin
  select * into v from public.trips where id = p_trip for update;
  if v is null or v.driver_id <> auth.uid() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v.status <> 'in_progress' then raise exception 'INVALID_TRIP_STATE' using errcode='P0001'; end if;
  update public.trips set status='completed', completed_at=now() where id = p_trip;
  update public.bookings set status='completed' where trip_id = p_trip and status='confirmed';
  for b in select * from public.bookings where trip_id = p_trip and status='completed' loop
    perform app.notify(b.client_id,'trip_completed','notifications.trip_completed.title','notifications.trip_completed.body',
                       jsonb_build_object('booking_id', b.id));
  end loop;
  perform app.audit('complete_trip','trip',p_trip,'{}'::jsonb);
end; $$;

create or replace function public.cancel_trip(p_trip uuid, p_reason text default null)
returns void language plpgsql security definer set search_path = public, app as $$
declare v record; b record; pay record; v_pct numeric;
begin
  select * into v from public.trips where id = p_trip for update;
  if v is null then raise exception 'NOT_FOUND' using errcode='P0001'; end if;
  if v.driver_id <> auth.uid() and not app.is_admin() then raise exception 'FORBIDDEN' using errcode='42501'; end if;
  if v.status in ('in_progress','completed','cancelled') then raise exception 'INVALID_TRIP_STATE' using errcode='P0001'; end if;

  -- Driver cancellation: all affected bookings are released and fully refunded (driver fault).
  for b in select * from public.bookings where trip_id = p_trip and status in ('pending','confirmed') for update loop
    perform app.move_seats(p_trip, b.pickup_checkpoint_id, b.dropoff_checkpoint_id, -b.seats);
    update public.bookings set status='cancelled' where id = b.id;
    update public.transfer_requests set status='cancelled', responded_at=now()
      where booking_id = b.id and status='pending';
    update public.resale_listings set status='cancelled', closed_at=now()
      where booking_id = b.id and status='open';
    select * into pay from public.booking_payments where booking_id = b.id and status in ('paid','authorized')
      order by created_at desc limit 1;
    if pay is not null then
      update public.booking_payments
        set status = (case when pay.status='paid' then 'refunded' else 'expired' end)::payment_status,
            refunded_amount = case when pay.status='paid' then pay.amount else 0 end
        where id = pay.id;
      perform app.audit('refund','booking_payment',pay.id,
        jsonb_build_object('reason','trip_cancelled','amount', case when pay.status='paid' then pay.amount else 0 end));
    end if;
    perform app.notify(b.client_id,'trip_cancelled','notifications.trip_cancelled.title','notifications.trip_cancelled.body',
                       jsonb_build_object('booking_id', b.id, 'trip_id', p_trip));
  end loop;

  update public.trips set status='cancelled', cancelled_at=now() where id = p_trip;
  perform app.audit('cancel_trip','trip',p_trip, jsonb_build_object('reason', p_reason));
end; $$;

----------------------------------------------------------------------
-- Search (database-driven, PostGIS, direction-aware)
----------------------------------------------------------------------
create or replace function public.search_trips(
  p_date date,
  p_from_lat float8 default null, p_from_lng float8 default null,
  p_to_lat float8 default null, p_to_lng float8 default null,
  p_seats int default 1,
  p_tolerance_m int default null,
  p_limit int default 20, p_offset int default 0
) returns table (
  trip_id uuid, driver_id uuid, driver_name text, driver_rating numeric,
  vehicle_brand text, vehicle_model text, vehicle_color text,
  departure_at timestamptz, booking_mode booking_mode,
  pickup_checkpoint_id uuid, pickup_name text, pickup_eta timestamptz,
  dropoff_checkpoint_id uuid, dropoff_name text, dropoff_eta timestamptz,
  price_per_seat numeric, available_seats int, total_distance_km numeric
) language sql stable security definer set search_path = public, app as $$
  with tol as (select coalesce(p_tolerance_m, app.setting_int('search_tolerance_meters',15000))::float8 m),
  src as (select case when p_from_lat is not null and p_from_lng is not null 
                  then st_setsrid(st_makepoint(p_from_lng,p_from_lat),4326)::geography 
                  else null end g),
  dst as (select case when p_to_lat is not null and p_to_lng is not null 
                  then st_setsrid(st_makepoint(p_to_lng,p_to_lat),4326)::geography 
                  else null end g),
  cand as (
    select t.id as trip_id, t.driver_id, t.departure_at, t.booking_mode, t.vehicle_id,
           a.id a_id, a.name a_name, a.sequence a_seq, a.estimated_arrival a_eta,
           b.id b_id, b.name b_name, b.sequence b_seq, b.estimated_arrival b_eta,
           case when (select g from src) is not null and (select g from dst) is not null
             then st_distance(a.location,(select g from src)) + st_distance(b.location,(select g from dst))
             else 0 end as detour
    from public.trips t
    join public.trip_checkpoints a on a.trip_id = t.id
    join public.trip_checkpoints b on b.trip_id = t.id
    cross join tol
    where t.status = 'published'
      and t.departure_at >= greatest(now(), p_date::timestamptz)
      and t.departure_at < (p_date + 1)::timestamptz
      and a.sequence < b.sequence
      and (case when (select g from src) is not null 
             then st_dwithin(a.location, (select g from src), tol.m) 
             else true end)
      and (case when (select g from dst) is not null 
             then st_dwithin(b.location, (select g from dst), tol.m) 
             else true end)
  ),
  best as (
    select distinct on (trip_id) * from cand order by trip_id, detour asc
  )
  select c.trip_id, c.driver_id, pr.full_name, pr.rating_avg,
         v.brand, v.model, v.color,
         c.departure_at, c.booking_mode,
         c.a_id, c.a_name, c.a_eta,
         c.b_id, c.b_name, c.b_eta,
         app.segment_price_sum(c.trip_id, c.a_id, c.b_id) as price_per_seat,
         (select min(g.capacity - g.reserved_seats)::int from public.trip_segments g
            where g.id in (select segment_id from app.covered_segment_ids(c.trip_id, c.a_id, c.b_id))) as available_seats,
         (select round(sum(g.distance_km),2) from public.trip_segments g
            where g.id in (select segment_id from app.covered_segment_ids(c.trip_id, c.a_id, c.b_id))) as total_distance_km
  from best c
  join public.public_profiles pr on pr.id = c.driver_id
  join public.vehicles v on v.id = c.vehicle_id
  where (select min(g.capacity - g.reserved_seats) from public.trip_segments g
          where g.id in (select segment_id from app.covered_segment_ids(c.trip_id, c.a_id, c.b_id))) >= greatest(p_seats,1)
  order by c.departure_at
  limit greatest(p_limit,1) offset greatest(p_offset,0);
$$;
