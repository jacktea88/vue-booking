-- 0007_bookings.sql
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
