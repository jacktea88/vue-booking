-- supabase/seed_dev.sql — creates demo auth users, a verified driver, vehicle and a published trip.
-- Run with the service role (e.g. `psql $DB_URL -f supabase/seed_dev.sql`) AFTER migrations.
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
