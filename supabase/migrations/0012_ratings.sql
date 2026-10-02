-- 0012_ratings.sql
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  from_user_id uuid not null references public.profiles(id) on delete cascade,
  to_user_id uuid not null references public.profiles(id) on delete cascade,
  rating int not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  unique (booking_id, from_user_id),
  check (from_user_id <> to_user_id)
);
create index if not exists ratings_to_user_idx on public.ratings(to_user_id);

create or replace function public.refresh_rating_aggregate()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  update public.profiles p set
    rating_avg = coalesce((select round(avg(r.rating)::numeric,2) from public.ratings r where r.to_user_id = new.to_user_id),0),
    rating_count = (select count(*) from public.ratings r where r.to_user_id = new.to_user_id)
  where p.id = new.to_user_id;
  return new;
end; $$;
drop trigger if exists ratings_aggregate on public.ratings;
create trigger ratings_aggregate after insert on public.ratings
  for each row execute function public.refresh_rating_aggregate();
