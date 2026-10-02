-- 0006_trips.sql
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
