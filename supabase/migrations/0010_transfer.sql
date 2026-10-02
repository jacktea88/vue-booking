-- 0010_transfer.sql
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
