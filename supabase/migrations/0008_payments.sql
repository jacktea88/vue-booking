-- 0008_payments.sql
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
