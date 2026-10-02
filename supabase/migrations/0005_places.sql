-- 0005_places.sql
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
