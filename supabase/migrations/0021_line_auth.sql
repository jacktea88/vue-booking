-- 0021_line_auth.sql
-- LINE Login (Web) identity mapping used by the Edge Function `line-auth`.
-- One LINE user (sub) maps to exactly one Supabase auth user. No automatic merge
-- with existing email/password accounts.
-- Access is service-role only: RLS is enabled with no policies and anon/authenticated
-- have no privileges.
create table if not exists public.line_identities (
  line_sub text primary key,
  user_id uuid not null unique references auth.users(id) on delete cascade,
  -- Informational only (LINE does not guarantee a verified email). Never used for account matching.
  line_email text,
  created_at timestamptz not null default now(),
  last_login_at timestamptz not null default now()
);
comment on table public.line_identities is 'LINE Login sub -> Supabase auth user mapping. Service role only.';

alter table public.line_identities enable row level security;
revoke all on public.line_identities from anon, authenticated;
