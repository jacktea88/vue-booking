-- 0009_resale.sql
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
