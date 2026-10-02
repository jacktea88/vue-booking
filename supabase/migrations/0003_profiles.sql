-- 0003_profiles.sql
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
