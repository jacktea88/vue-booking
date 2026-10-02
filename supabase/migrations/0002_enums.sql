-- 0002_enums.sql
do $$ begin
  create type user_role as enum ('client','driver','admin');
  create type identity_status as enum ('pending','verified','rejected');
  create type document_type as enum ('identity_card','driving_license','vehicle_registration','insurance');
  create type document_status as enum ('pending','verified','rejected');
  create type place_type as enum ('wilaya','commune','station','place','custom');
  create type trip_status as enum ('draft','published','boarding','in_progress','completed','cancelled');
  create type booking_mode as enum ('auto_confirm','driver_approval');
  create type booking_status as enum ('pending','confirmed','rejected','cancelled','completed','no_show');
  create type booking_source as enum ('direct','resale');
  create type payment_status as enum ('requires_payment','authorized','paid','failed','expired','refunded','partially_refunded');
  create type resale_status as enum ('open','closed','cancelled');
  create type transfer_status as enum ('pending','approved','rejected','cancelled');
exception when duplicate_object then null; end $$;
