-- 0015_rls.sql  Row Level Security
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
