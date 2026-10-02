-- 0001_extensions.sql
create extension if not exists postgis;
create extension if not exists pgcrypto;

create schema if not exists app;

-- Generic helper with no table dependencies.
-- Security/settings helpers live in 0015_security_helpers.sql, because their
-- SQL bodies are validated at creation time and reference tables created later.
create or replace function app.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;
