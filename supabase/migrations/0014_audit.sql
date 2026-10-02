-- 0014_audit.sql
create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists audit_created_idx on public.audit_logs(created_at desc);
create index if not exists audit_entity_idx on public.audit_logs(entity_type, entity_id);

create or replace function app.audit(p_action text, p_entity text, p_entity_id uuid, p_meta jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public, app as $$
  insert into public.audit_logs(actor_id, action, entity_type, entity_id, metadata)
  values (auth.uid(), p_action, p_entity, p_entity_id, coalesce(p_meta,'{}'::jsonb));
$$;

create or replace function app.notify(p_user uuid, p_type text, p_title text, p_body text, p_data jsonb default '{}'::jsonb)
returns void language sql security definer set search_path = public, app as $$
  insert into public.notifications(user_id, type, title, body, data)
  values (p_user, p_type, p_title, coalesce(p_body,''), coalesce(p_data,'{}'::jsonb));
$$;
