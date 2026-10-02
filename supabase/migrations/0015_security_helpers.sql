-- 0015_security_helpers.sql
-- Authorization + settings helpers. Defined AFTER profiles/settings exist because
-- `language sql` bodies are parsed and validated at creation time.

-- Role is always read from the profiles table, never from client-supplied JWT claims.
create or replace function app.current_role()
returns text language sql stable security definer set search_path = public, app as $$
  select p.role::text from public.profiles p where p.id = auth.uid();
$$;

create or replace function app.is_admin()
returns boolean language sql stable security definer set search_path = public, app as $$
  select coalesce((select p.role = 'admin' from public.profiles p where p.id = auth.uid()), false);
$$;

create or replace function app.setting_int(p_key text, p_default int)
returns int language sql stable security definer set search_path = public, app as $$
  select coalesce((select (value #>> '{}')::int from public.settings where key = p_key), p_default);
$$;

create or replace function app.setting_num(p_key text, p_default numeric)
returns numeric language sql stable security definer set search_path = public, app as $$
  select coalesce((select (value #>> '{}')::numeric from public.settings where key = p_key), p_default);
$$;
