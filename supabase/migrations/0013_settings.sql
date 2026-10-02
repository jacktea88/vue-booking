-- 0013_settings.sql
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
