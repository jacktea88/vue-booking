-- ========================================================================
-- VUE-BOOKING SUPABASE DATABASE SCHEMA
-- Complete migration script combining all migrations (0001-0020) + seed_dev
-- This script can be executed in Supabase SQL Editor
-- ========================================================================

-- ========================================================================
-- 0001_extensions.sql — Extensions and base helpers
-- ========================================================================
create extension if not exists postgis;
create extension if not exists pgcrypto;

create schema if not exists app;

-- Generic helper with no table dependencies.
-- Security/settings helpers live in 0015_security_helpers.sql, because their
-- SQL bodies are validated at creation time and reference tables created later.
create or replace function app.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

-- ========================================================================
-- 0002_enums.sql — All enumerated types
-- ========================================================================
do $$ begin
  create type user_role as enum ('client','driver','admin');
  create type identity_status as enum ('pending','verified','rejected');
  create type document_type as enum ('identity_card','driving_license','vehicle_registration','insurance');
  create type document_status as enum ('pending','verified','rejected');
  create type place_type as enum ('wilaya','commune','station','place','custom');
  create type trip_status as enum ('draft','published','boarding','in_progress','completed','cancelled');
  create type booking_mode as enum ('auto_confirm','driver_approval');
  create type booking_status as enum ('pending','confirmed','rejected','cancelled','completed','no_show');
  create type booking_source as enum ('direct','resale');
  create type payment_status as enum ('requires_payment','authorized','paid','failed','expired','refunded','partially_refunded');
  create type resale_status as enum ('open','closed','cancelled');
  create type transfer_status as enum ('pending','approved','rejected','cancelled');
exception when duplicate_object then null; end $$;

-- ========================================================================
-- 0003_profiles.sql — User profiles and driver profiles
-- ========================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role user_role not null default 'client',
  full_name text not null default '',
  phone text,
  photo_url text,
  identity_status identity_status not null default 'pending',
  rating_avg numeric(3,2) not null default 0 check (rating_avg >= 0 and rating_avg <= 5),
  rating_count int not null default 0 check (rating_count >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists profiles_role_idx on public.profiles(role);
drop trigger if exists profiles_touch on public.profiles;
create trigger profiles_touch before update on public.profiles
  for each row execute function app.touch_updated_at();

create table if not exists public.driver_profiles (
  id uuid primary key references public.profiles(id) on delete cascade,
  license_number text,
  overall_verified boolean not null default false,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists driver_profiles_touch on public.driver_profiles;
create trigger driver_profiles_touch before update on public.driver_profiles
  for each row execute function app.touch_updated_at();

-- Role is never taken from the client payload: signup metadata only allows client|driver.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_role user_role;
begin
  v_role := case lower(coalesce(new.raw_user_meta_data->>'role',''))
              when 'driver' then 'driver'::user_role
              else 'client'::user_role end;
  insert into public.profiles(id, role, full_name, phone)
  values (new.id, v_role, coalesce(new.raw_user_meta_data->>'full_name',''), new.raw_user_meta_data->>'phone')
  on conflict (id) do nothing;
  if v_role = 'driver' then
    insert into public.driver_profiles(id) values (new.id) on conflict (id) do nothing;
  end if;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Guard: nobody except admins (or SECURITY DEFINER routines) may change role / identity_status.
create or replace function public.guard_profile_update()
returns trigger language plpgsql security definer set search_path = public, app as $$
begin
  if (new.role is distinct from old.role or new.identity_status is distinct from old.identity_status)
     and auth.uid() is not null and not app.is_admin() then
    raise exception 'FORBIDDEN_FIELD_UPDATE' using errcode = '42501';
  end if;
  return new;
end; $$;
drop trigger if exists profiles_guard on public.profiles;
create trigger profiles_guard before update on public.profiles
  for each row execute function public.guard_profile_update();

-- ========================================================================
-- 0004_verification.sql — Verification documents and vehicles
-- ========================================================================
create table if not exists public.verification_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type document_type not null,
  storage_path text not null,
  status document_status not null default 'pending',
  rejection_reason text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists verif_user_idx on public.verification_documents(user_id);
create index if not exists verif_status_idx on public.verification_documents(status, created_at desc);
drop trigger if exists verif_touch on public.verification_documents;
create trigger verif_touch before update on public.verification_documents
  for each row execute function app.touch_updated_at();

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null unique references public.profiles(id) on delete cascade,
  brand text not null,
  model text not null,
  color text not null,
  plate_number text not null,
  capacity int not null check (capacity > 0 and capacity <= 8),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists vehicles_touch on public.vehicles;
create trigger vehicles_touch before update on public.vehicles
  for each row execute function app.touch_updated_at();

-- ========================================================================
-- 0005_places.sql — Places (stations, wilayas, communes, custom points)
-- ========================================================================
create table if not exists public.places (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type place_type not null default 'place',
  wilaya text,
  commune text,
  location geography(point,4326) not null,
  is_custom boolean not null default false,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists places_location_gix on public.places using gist(location);
create index if not exists places_name_idx on public.places (lower(name));
create index if not exists places_wilaya_idx on public.places(wilaya);

-- ========================================================================
-- 0006_trips.sql — Trips, checkpoints, and segments
-- ========================================================================
create table if not exists public.trips (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null references public.profiles(id) on delete cascade,
  vehicle_id uuid not null references public.vehicles(id) on delete restrict,
  departure_at timestamptz not null,
  status trip_status not null default 'draft',
  booking_mode booking_mode not null default 'auto_confirm',
  published_at timestamptz,
  started_at timestamptz,
  completed_at timestamptz,
  cancelled_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists trips_driver_idx on public.trips(driver_id, departure_at desc);
create index if not exists trips_status_dep_idx on public.trips(status, departure_at);
drop trigger if exists trips_touch on public.trips;
create trigger trips_touch before update on public.trips
  for each row execute function app.touch_updated_at();

create table if not exists public.trip_checkpoints (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  place_id uuid references public.places(id) on delete set null,
  name text not null,
  location geography(point,4326) not null,
  sequence int not null check (sequence >= 0),
  estimated_arrival timestamptz,
  created_at timestamptz not null default now(),
  unique (trip_id, sequence)
);
create index if not exists checkpoints_trip_idx on public.trip_checkpoints(trip_id, sequence);
create index if not exists checkpoints_loc_gix on public.trip_checkpoints using gist(location);

create table if not exists public.trip_segments (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips(id) on delete cascade,
  from_checkpoint_id uuid not null references public.trip_checkpoints(id) on delete cascade,
  to_checkpoint_id uuid not null references public.trip_checkpoints(id) on delete cascade,
  sequence int not null check (sequence >= 0),
  distance_km numeric(10,2) not null check (distance_km >= 0),
  estimated_minutes int not null check (estimated_minutes >= 0),
  reference_price numeric(10,2) not null check (reference_price >= 0),
  driver_price numeric(10,2) not null check (driver_price >= 0),
  capacity int not null check (capacity > 0),
  reserved_seats int not null default 0 check (reserved_seats >= 0),
  created_at timestamptz not null default now(),
  unique (trip_id, sequence),
  check (reserved_seats <= capacity)
);
create index if not exists segments_trip_idx on public.trip_segments(trip_id, sequence);

-- ========================================================================
-- 0007_bookings.sql — Booking table and constraints
-- ========================================================================
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.profiles(id) on delete cascade,
  trip_id uuid not null references public.trips(id) on delete cascade,
  pickup_checkpoint_id uuid not null references public.trip_checkpoints(id) on delete cascade,
  dropoff_checkpoint_id uuid not null references public.trip_checkpoints(id) on delete cascade,
  seats int not null check (seats > 0),
  price_per_seat numeric(10,2) not null check (price_per_seat >= 0),
  total_amount numeric(12,2) not null check (total_amount >= 0),
  status booking_status not null default 'pending',
  source booking_source not null default 'direct',
  approval_expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (pickup_checkpoint_id <> dropoff_checkpoint_id)
);
create index if not exists bookings_client_idx on public.bookings(client_id, created_at desc);
create index if not exists bookings_trip_idx on public.bookings(trip_id, status);
create index if not exists bookings_status_idx on public.bookings(status);
drop trigger if exists bookings_touch on public.bookings;
create trigger bookings_touch before update on public.bookings
  for each row execute function app.touch_updated_at();

-- Financial snapshot guard.
-- `price_per_seat` is frozen once the booking is confirmed. `total_amount` may only
-- change as a consequence of a seat-count change (resale), and must always stay
-- exactly seats * the frozen per-seat price.
create or replace function public.guard_booking_price()
returns trigger language plpgsql as $$
begin
  if old.status in ('confirmed','completed') then
    if new.price_per_seat is distinct from old.price_per_seat then
      raise exception 'BOOKING_PRICE_IMMUTABLE' using errcode = '22000';
    end if;
    if new.total_amount is distinct from (new.seats * old.price_per_seat) then
      raise exception 'BOOKING_PRICE_IMMUTABLE' using errcode = '22000';
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists bookings_price_guard on public.bookings;
create trigger bookings_price_guard before update on public.bookings
  for each row execute function public.guard_booking_price();

-- ========================================================================
-- 0008_payments.sql — Payment tracking
-- ========================================================================
create table if not exists public.booking_payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  amount numeric(12,2) not null check (amount >= 0),
  currency text not null default 'DZD',
  status payment_status not null default 'requires_payment',
  provider text not null default 'mock',
  provider_reference text,
  paid_at timestamptz,
  refunded_amount numeric(12,2) not null default 0 check (refunded_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (refunded_amount <= amount)
);
create index if not exists payments_booking_idx on public.booking_payments(booking_id, created_at desc);
create index if not exists payments_status_idx on public.booking_payments(status);
drop trigger if exists payments_touch on public.booking_payments;
create trigger payments_touch before update on public.booking_payments
  for each row execute function app.touch_updated_at();

-- ========================================================================
-- 0009_resale.sql — Resale listings
-- ========================================================================
create table if not exists public.resale_listings (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  seller_id uuid not null references public.profiles(id) on delete cascade,
  seats_for_sale int not null check (seats_for_sale > 0),
  seats_sold int not null default 0 check (seats_sold >= 0),
  price_per_seat numeric(10,2) not null check (price_per_seat >= 0),
  status resale_status not null default 'open',
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  check (seats_sold <= seats_for_sale)
);
create index if not exists resale_status_idx on public.resale_listings(status, created_at desc);
create index if not exists resale_booking_idx on public.resale_listings(booking_id);
create unique index if not exists resale_one_open_per_booking
  on public.resale_listings(booking_id) where status = 'open';

-- ========================================================================
-- 0010_transfer.sql — Transfer requests
-- ========================================================================
create table if not exists public.transfer_requests (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  from_trip_id uuid not null references public.trips(id) on delete cascade,
  to_trip_id uuid not null references public.trips(id) on delete cascade,
  to_pickup_checkpoint_id uuid references public.trip_checkpoints(id) on delete set null,
  to_dropoff_checkpoint_id uuid references public.trip_checkpoints(id) on delete set null,
  requested_by uuid not null references public.profiles(id) on delete cascade,
  status transfer_status not null default 'pending',
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (from_trip_id <> to_trip_id)
);
create index if not exists transfer_booking_idx on public.transfer_requests(booking_id, status);
create unique index if not exists transfer_one_pending_per_booking
  on public.transfer_requests(booking_id) where status = 'pending';

-- ========================================================================
-- 0011_notifications.sql — Notifications and push subscriptions
-- ========================================================================
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null,
  title text not null,
  body text not null default '',
  data jsonb not null default '{}'::jsonb,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists notif_user_idx on public.notifications(user_id, created_at desc);
create index if not exists notif_unread_idx on public.notifications(user_id) where read_at is null;

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null default 'web',
  created_at timestamptz not null default now(),
  unique (user_id, token)
);

-- ========================================================================
-- 0012_ratings.sql — User ratings
-- ========================================================================
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  from_user_id uuid not null references public.profiles(id) on delete cascade,
  to_user_id uuid not null references public.profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (booking_id, from_user_id),
  check (from_user_id <> to_user_id)
);
create index if not exists ratings_to_user_idx on public.ratings(to_user_id);

create or replace function public.refresh_rating_aggregate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles p set
    rating_avg = coalesce((select round(avg(r.rating)::numeric,2) from public.ratings r where r.to_user_id = new.to_user_id),0),
    rating_count = (select count(*) from public.ratings r where r.to_user_id = new.to_user_id)
  where p.id = new.to_user_id;
  return new;
end; $$;
drop trigger if exists ratings_aggregate on public.ratings;
create trigger ratings_aggregate after insert on public.ratings
  for each row execute function public.refresh_rating_aggregate();

-- ========================================================================
-- 0013_settings.sql — Application settings
-- ========================================================================
create table if not exists public.settings (
  key text primary key,
  value jsonb not null,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into public.settings(key, value) values
  ('booking_approval_timeout_minutes', '30'::jsonb),
  ('payment_timeout_minutes', '15'::jsonb),
  ('resale_payment_timeout_minutes', '15'::jsonb),
  ('cancellation_window_hours', '24'::jsonb),
  ('cancellation_min_minutes_after_booking', '30'::jsonb),
  ('refund_percentage', '80'::jsonb),
  ('price_base_dzd', '50'::jsonb),
  ('price_per_km_dzd', '8'::jsonb),
  ('price_rounding_dzd', '50'::jsonb),
  ('search_tolerance_meters', '15000'::jsonb),
  ('average_speed_kmh', '70'::jsonb)
on conflict (key) do nothing;

-- ========================================================================
-- 0014_audit.sql — Audit logging and helper functions
-- ========================================================================
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_created_idx on public.audit_logs(created_at desc);
create index if not exists audit_entity_idx on public.audit_logs(entity_type, entity_id);

create or replace function app.audit(p_action text, p_entity text, p_entity_id uuid, p_meta jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public, app as $$
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_meta,'{}'::jsonb));
$$;

create or replace function app.notify(p_user uuid, p_type text, p_title text, p_body text, p_data jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public, app as $$
  insert into public.notifications(user_id, type, title, body, data)
  values (p_user, p_type, p_title, coalesce(p_body,''), coalesce(p_data,'{}'::jsonb));
$$;

-- ========================================================================
-- 0015_security_helpers.sql — Authorization and settings helpers
-- ========================================================================
-- Authorization + settings helpers. Defined AFTER profiles/settings exist because
-- `language sql` bodies are parsed and validated at creation time.

-- Role is always read from the profiles table, never from client-supplied JWT claims.
create or replace function app.current_role()
returns text language sql stable security definer set search_path = public, app as $$
  select p.role::text from public.profiles p where p.id = auth.uid();
$$;

create or replace function app.is_admin()
returns boolean language sql stable security definer set search_path = public, app as $$
  select coalesce((select p.role = 'admin' from public.profiles p where p.id = auth.uid()), false);
$$;

create or replace function app.setting_int(p_key text, p_default int)
returns int language sql stable security definer set search_path = public, app as $$
  select coalesce((select (value #>> '{}')::int from public.settings where key = p_key), p_default);
$$;

create or replace function app.setting_num(p_key text, p_default numeric)
returns numeric language sql stable security definer set search_path = public, app as $$
  select coalesce((select (value #>> '{}')::numeric from public.settings where key = p_key), p_default);
$$;

-- ========================================================================
-- 0016_rls.sql — Row Level Security policies
-- ========================================================================
alter table public.profiles enable row level security;
alter table public.driver_profiles enable row level security;
alter table public.verification_documents enable row level security;
alter table public.vehicles enable row level security;
alter table public.places enable row level security;
alter table public.trips enable row level security;
alter table public.trip_checkpoints enable row level security;
alter table public.trip_segments enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_payments enable row level security;
alter table public.resale_listings enable row level security;
alter table public.transfer_requests enable row level security;
alter table public.notifications enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.ratings enable row level security;
alter table public.settings enable row level security;
alter table public.audit_logs enable row level security;

-- profiles: own row + public read of counterpart basics is handled through views/RPC.
drop policy if exists profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = auth.uid() or app.is_admin());
drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles for update to authenticated
  using (id = auth.uid() or app.is_admin()) with check (id = auth.uid() or app.is_admin());

drop policy if exists driver_profiles_select on public.driver_profiles;
create policy driver_profiles_select on public.driver_profiles for select to authenticated
  using (id = auth.uid() or app.is_admin());
drop policy if exists driver_profiles_update on public.driver_profiles;
create policy driver_profiles_update on public.driver_profiles for update to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- verification documents
drop policy if exists verif_select on public.verification_documents;
create policy verif_select on public.verification_documents for select to authenticated
  using (user_id = auth.uid() or app.is_admin());
drop policy if exists verif_insert on public.verification_documents;
create policy verif_insert on public.verification_documents for insert to authenticated
  with check (user_id = auth.uid());
drop policy if exists verif_update_admin on public.verification_documents;
create policy verif_update_admin on public.verification_documents for update to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- vehicles
drop policy if exists vehicles_select on public.vehicles;
create policy vehicles_select on public.vehicles for select to authenticated using (true);
drop policy if exists vehicles_cud on public.vehicles;
create policy vehicles_cud on public.vehicles for all to authenticated
  using (driver_id = auth.uid() or app.is_admin())
  with check (driver_id = auth.uid() or app.is_admin());

-- places (global catalogue readable, custom points insertable by owner)
drop policy if exists places_select on public.places;
create policy places_select on public.places for select to authenticated using (true);
drop policy if exists places_insert on public.places;
create policy places_insert on public.places for insert to authenticated
  with check (is_custom and created_by = auth.uid());

-- trips
drop policy if exists trips_select on public.trips;
create policy trips_select on public.trips for select to authenticated
  using (status <> 'draft' or driver_id = auth.uid() or app.is_admin());
drop policy if exists trips_cud on public.trips;
create policy trips_cud on public.trips for all to authenticated
  using (driver_id = auth.uid() or app.is_admin())
  with check (driver_id = auth.uid() or app.is_admin());

drop policy if exists checkpoints_select on public.trip_checkpoints;
create policy checkpoints_select on public.trip_checkpoints for select to authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id
                 and (t.status <> 'draft' or t.driver_id = auth.uid() or app.is_admin())));
drop policy if exists checkpoints_cud on public.trip_checkpoints;
create policy checkpoints_cud on public.trip_checkpoints for all to authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id and (t.driver_id = auth.uid() or app.is_admin())))
  with check (exists (select 1 from public.trips t where t.id = trip_id and (t.driver_id = auth.uid() or app.is_admin())));

drop policy if exists segments_select on public.trip_segments;
create policy segments_select on public.trip_segments for select to authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id
                 and (t.status <> 'draft' or t.driver_id = auth.uid() or app.is_admin())));
-- Seat inventory is only mutated by SECURITY DEFINER RPCs; drivers may only price before publishing.
drop policy if exists segments_update_price on public.trip_segments;
create policy segments_update_price on public.trip_segments for update to authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id and t.driver_id = auth.uid() and t.status = 'draft'))
  with check (exists (select 1 from public.trips t where t.id = trip_id and t.driver_id = auth.uid() and t.status = 'draft'));

-- bookings
drop policy if exists bookings_select on public.bookings;
create policy bookings_select on public.bookings for select to authenticated
  using (client_id = auth.uid()
         or exists (select 1 from public.trips t where t.id = trip_id and t.driver_id = auth.uid())
         or app.is_admin());
-- writes go through RPCs only (no insert/update policy for normal users)
drop policy if exists bookings_admin_all on public.bookings;
create policy bookings_admin_all on public.bookings for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- payments: client reads own, admin all. Drivers get no provider data.
drop policy if exists payments_select on public.booking_payments;
create policy payments_select on public.booking_payments for select to authenticated
  using (exists (select 1 from public.bookings b where b.id = booking_id and b.client_id = auth.uid())
         or app.is_admin());
drop policy if exists payments_admin_all on public.booking_payments;
create policy payments_admin_all on public.booking_payments for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- resale
drop policy if exists resale_select on public.resale_listings;
create policy resale_select on public.resale_listings for select to authenticated using (true);
drop policy if exists resale_admin on public.resale_listings;
create policy resale_admin on public.resale_listings for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- transfers
drop policy if exists transfer_select on public.transfer_requests;
create policy transfer_select on public.transfer_requests for select to authenticated
  using (requested_by = auth.uid()
         or exists (select 1 from public.bookings b where b.id = booking_id and b.client_id = auth.uid())
         or app.is_admin());
drop policy if exists transfer_admin on public.transfer_requests;
create policy transfer_admin on public.transfer_requests for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- notifications
drop policy if exists notif_select on public.notifications;
create policy notif_select on public.notifications for select to authenticated using (user_id = auth.uid() or app.is_admin());
drop policy if exists notif_update on public.notifications;
create policy notif_update on public.notifications for update to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists push_all on public.push_subscriptions;
create policy push_all on public.push_subscriptions for all to authenticated
  using (user_id = auth.uid()) with check (user_id = auth.uid());

-- ratings: participants only (enforced again inside RPC)
drop policy if exists ratings_select on public.ratings;
create policy ratings_select on public.ratings for select to authenticated
  using (from_user_id = auth.uid() or to_user_id = auth.uid() or app.is_admin());
drop policy if exists ratings_admin on public.ratings;
create policy ratings_admin on public.ratings for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- settings: readable by all authenticated, writable by admin
drop policy if exists settings_select on public.settings;
create policy settings_select on public.settings for select to authenticated using (true);
drop policy if exists settings_admin on public.settings;
create policy settings_admin on public.settings for all to authenticated
  using (app.is_admin()) with check (app.is_admin());

-- audit logs: admin only
drop policy if exists audit_admin on public.audit_logs;
create policy audit_admin on public.audit_logs for select to authenticated using (app.is_admin());

-- Public profile projection used in trip cards (no phone / no identity data).
create or replace view public.public_profiles
with (security_invoker = off) as
  select id, full_name, photo_url, rating_avg, rating_count, role from public.profiles;
grant select on public.public_profiles to authenticated, anon;

-- ========================================================================
-- 0017_functions_trips.sql — Trip management and search functions
-- ========================================================================
-- Domain RPC layer. All critical operations are transactional + row-locking.
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
  p_from_lat float8, p_from_lng float8,
  p_to_lat float8, p_to_lng float8,
  p_date date, p_seats int default 1,
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
  src as (select st_setsrid(st_makepoint(p_from_lng,p_from_lat),4326)::geography g),
  dst as (select st_setsrid(st_makepoint(p_to_lng,p_to_lat),4326)::geography g),
  cand as (
    select t.id as trip_id, t.driver_id, t.departure_at, t.booking_mode, t.vehicle_id,
           a.id a_id, a.name a_name, a.sequence a_seq, a.estimated_arrival a_eta,
           b.id b_id, b.name b_name, b.sequence b_seq, b.estimated_arrival b_eta,
           st_distance(a.location,(select g from src)) + st_distance(b.location,(select g from dst)) as detour
    from public.trips t
    join public.trip_checkpoints a on a.trip_id = t.id
    join public.trip_checkpoints b on b.trip_id = t.id
    cross join tol
    where t.status = 'published'
      and t.departure_at >= greatest(now(), p_date::timestamptz)
      and t.departure_at < (p_date + 1)::timestamptz
      and a.sequence < b.sequence
      and st_dwithin(a.location, (select g from src), tol.m)
      and st_dwithin(b.location, (select g from dst), tol.m)
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

-- ========================================================================
-- 0018_functions_booking.sql — Booking, payment, and transfer functions
-- ========================================================================
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

-- ========================================================================
-- 0019_storage.sql — Storage buckets and policies
-- ========================================================================
insert into storage.buckets (id, name, public)
values ('avatars','avatars', true) on conflict (id) do nothing;
insert into storage.buckets (id, name, public)
values ('verification-documents','verification-documents', false) on conflict (id) do nothing;

-- avatars: public read, owner writes under <uid>/...
drop policy if exists avatars_read on storage.objects;
create policy avatars_read on storage.objects for select
  using (bucket_id = 'avatars');
drop policy if exists avatars_write on storage.objects;
create policy avatars_write on storage.objects for insert to authenticated
  with check (bucket_id='avatars' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists avatars_update on storage.objects;
create policy avatars_update on storage.objects for update to authenticated
  using (bucket_id='avatars' and (storage.foldername(name))[1] = auth.uid()::text);

-- verification documents: strictly private, owner upload, owner+admin read (signed URLs)
drop policy if exists verifdocs_read on storage.objects;
create policy verifdocs_read on storage.objects for select to authenticated
  using (bucket_id='verification-documents'
         and ((storage.foldername(name))[1] = auth.uid()::text or app.is_admin()));
drop policy if exists verifdocs_write on storage.objects;
create policy verifdocs_write on storage.objects for insert to authenticated
  with check (bucket_id='verification-documents' and (storage.foldername(name))[1] = auth.uid()::text);
drop policy if exists verifdocs_delete on storage.objects;
create policy verifdocs_delete on storage.objects for delete to authenticated
  using (bucket_id='verification-documents' and (storage.foldername(name))[1] = auth.uid()::text);

-- ========================================================================
-- 0020_seed.sql — Development seed data
-- ========================================================================
insert into public.settings(key,value) values ('allow_mock_payments','true'::jsonb), ('payment_provider','"mock"'::jsonb)
on conflict (key) do nothing;

insert into public.places (name, type, wilaya, commune, location) values
 ('Alger Centre','wilaya','Alger','Alger Centre', st_setsrid(st_makepoint(3.0588,36.7538),4326)),
 ('Blida','wilaya','Blida','Blida', st_setsrid(st_makepoint(2.8277,36.4703),4326)),
 ('Médéa','wilaya','Médéa','Médéa', st_setsrid(st_makepoint(2.7539,36.2675),4326)),
 ('Laghouat','wilaya','Laghouat','Laghouat', st_setsrid(st_makepoint(2.8650,33.8000),4326)),
 ('Oran','wilaya','Oran','Oran', st_setsrid(st_makepoint(-0.6331,35.6971),4326)),
 ('Constantine','wilaya','Constantine','Constantine', st_setsrid(st_makepoint(6.6147,36.3650),4326)),
 ('Annaba','wilaya','Annaba','Annaba', st_setsrid(st_makepoint(7.7667,36.9000),4326)),
 ('Sétif','wilaya','Sétif','Sétif', st_setsrid(st_makepoint(5.4108,36.1898),4326)),
 ('Tizi Ouzou','wilaya','Tizi Ouzou','Tizi Ouzou', st_setsrid(st_makepoint(4.0500,36.7169),4326)),
 ('Béjaïa','wilaya','Béjaïa','Béjaïa', st_setsrid(st_makepoint(5.0833,36.7500),4326)),
 ('Ghardaïa','wilaya','Ghardaïa','Ghardaïa', st_setsrid(st_makepoint(3.6667,32.4833),4326)),
 ('Ouargla','wilaya','Ouargla','Ouargla', st_setsrid(st_makepoint(5.3333,31.9500),4326)),
 ('Batna','wilaya','Batna','Batna', st_setsrid(st_makepoint(6.1739,35.5559),4326)),
 ('Tlemcen','wilaya','Tlemcen','Tlemcen', st_setsrid(st_makepoint(-1.3150,34.8828),4326)),
 ('Biskra','wilaya','Biskra','Biskra', st_setsrid(st_makepoint(5.7281,34.8500),4326)),
 ('Gare Routière Kharrouba','station','Alger','Kharrouba', st_setsrid(st_makepoint(3.0960,36.7100),4326)),
 ('Aéroport Houari Boumediene','station','Alger','Dar El Beïda', st_setsrid(st_makepoint(3.2154,36.6910),4326))
on conflict do nothing;

-- ========================================================================
-- seed_dev.sql — Demo auth users and test data
-- ========================================================================
-- Creates demo auth users, a verified driver, vehicle and a published trip.
-- Run AFTER all migrations.
-- Demo password for every account: Passw0rd!
do $$
declare v_client uuid; v_client2 uuid; v_driver uuid; v_admin uuid; v_trip uuid; v_veh uuid;
        cp jsonb;
begin
  -- auth users
  insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values
   ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),'authenticated','authenticated','client@demo.test',
    crypt('Passw0rd!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
    '{"full_name":"Amina Demo","role":"client"}', now(), now())
  returning id into v_client;

  insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),'authenticated','authenticated','client2@demo.test',
    crypt('Passw0rd!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
    '{"full_name":"Yacine Demo","role":"client"}', now(), now())
  returning id into v_client2;

  insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),'authenticated','authenticated','driver@demo.test',
    crypt('Passw0rd!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
    '{"full_name":"Karim Demo","role":"driver"}', now(), now())
  returning id into v_driver;

  insert into auth.users (instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at)
  values ('00000000-0000-0000-0000-000000000000', gen_random_uuid(),'authenticated','authenticated','admin@demo.test',
    crypt('Passw0rd!', gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}',
    '{"full_name":"Admin Demo","role":"client"}', now(), now())
  returning id into v_admin;

  -- GoTrue scans these token columns into Go strings and fails on NULL,
  -- so manually-seeded users must carry empty strings instead.
  update auth.users set
    confirmation_token = coalesce(confirmation_token,''),
    recovery_token = coalesce(recovery_token,''),
    email_change_token_new = coalesce(email_change_token_new,''),
    email_change_token_current = coalesce(email_change_token_current,''),
    email_change = coalesce(email_change,''),
    phone_change = coalesce(phone_change,''),
    phone_change_token = coalesce(phone_change_token,''),
    reauthentication_token = coalesce(reauthentication_token,'')
  where id in (v_client, v_client2, v_driver, v_admin);

  insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
  select gen_random_uuid(), u.id, u.id::text, jsonb_build_object('sub',u.id::text,'email',u.email), 'email', now(), now(), now()
  from auth.users u where u.email in ('client@demo.test','client2@demo.test','driver@demo.test','admin@demo.test')
  on conflict do nothing;

  -- admin bootstrap (server-side only)
  update public.profiles set role='admin', identity_status='verified' where id = v_admin;
  update public.profiles set identity_status='verified' where id in (v_client, v_client2, v_driver);

  -- verified driver + vehicle
  insert into public.driver_profiles(id, license_number, overall_verified, verified_at)
  values (v_driver,'DEMO-LIC-001', true, now())
  on conflict (id) do update set overall_verified = true, verified_at = now();

  insert into public.verification_documents(user_id,type,storage_path,status,reviewed_by,reviewed_at)
  select v_driver, t::document_type, v_driver || '/' || t || '.jpg', 'verified', v_admin, now()
  from unnest(array['identity_card','driving_license','vehicle_registration','insurance']) t;

  insert into public.vehicles(driver_id,brand,model,color,plate_number,capacity)
  values (v_driver,'Renault','Symbol','Blanc','00123-116-16', 4)
  on conflict (driver_id) do update set capacity = 4
  returning id into v_veh;

  -- published trip Alger → Blida → Médéa → Laghouat (built through the real RPC path)
  insert into public.trips(driver_id,vehicle_id,departure_at,booking_mode,status,published_at)
  values (v_driver, v_veh, now() + interval '3 days', 'auto_confirm','published', now())
  returning id into v_trip;

  insert into public.trip_checkpoints(trip_id,name,location,sequence,estimated_arrival) values
    (v_trip,'Alger Centre', st_setsrid(st_makepoint(3.0588,36.7538),4326), 0, now() + interval '3 days'),
    (v_trip,'Blida',        st_setsrid(st_makepoint(2.8277,36.4703),4326), 1, now() + interval '3 days 45 minutes'),
    (v_trip,'Médéa',        st_setsrid(st_makepoint(2.7539,36.2675),4326), 2, now() + interval '3 days 1 hour 30 minutes'),
    (v_trip,'Laghouat',     st_setsrid(st_makepoint(2.8650,33.8000),4326), 3, now() + interval '3 days 5 hours');

  insert into public.trip_segments(trip_id,from_checkpoint_id,to_checkpoint_id,sequence,distance_km,estimated_minutes,
                                   reference_price,driver_price,capacity)
  select v_trip, a.id, b.id, a.sequence,
         round((st_distance(a.location,b.location)/1000.0)::numeric,2),
         greatest(ceil((st_distance(a.location,b.location)/1000.0)/70*60)::int,1),
         app.reference_price(round((st_distance(a.location,b.location)/1000.0)::numeric,2)),
         app.reference_price(round((st_distance(a.location,b.location)/1000.0)::numeric,2)),
         4
  from public.trip_checkpoints a
  join public.trip_checkpoints b on b.trip_id = a.trip_id and b.sequence = a.sequence + 1
  where a.trip_id = v_trip;

  raise notice 'Seed complete. client=% driver=% admin=%', v_client, v_driver, v_admin;
end $$;

-- ========================================================================
-- END OF COMBINED MIGRATIONS SCRIPT
-- ========================================================================
-- This script includes all 20 migrations plus development seed data.
-- You can now execute this in Supabase SQL Editor.
-- ========================================================================
