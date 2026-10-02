-- 0004_verification.sql
create table if not exists public.verification_documents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  type document_type not null,
  storage_path text not null,
  status document_status not null default 'pending',
  rejection_reason text,
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists verif_user_idx on public.verification_documents(user_id);
create index if not exists verif_status_idx on public.verification_documents(status, created_at desc);
drop trigger if exists verif_touch on public.verification_documents;
create trigger verif_touch before update on public.verification_documents
  for each row execute function app.touch_updated_at();

create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  driver_id uuid not null unique references public.profiles(id) on delete cascade,
  brand text not null,
  model text not null,
  color text not null,
  plate_number text not null,
  capacity int not null check (capacity > 0 and capacity <= 8),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
drop trigger if exists vehicles_touch on public.vehicles;
create trigger vehicles_touch before update on public.vehicles
  for each row execute function app.touch_updated_at();
