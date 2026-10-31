# Wassalni — Ride booking & carpooling for Algeria

Production-oriented MVP: **Vue 3 + TypeScript + Vite + Tailwind CSS v4** on the frontend,
**Supabase (PostgreSQL + PostGIS + Auth + Storage + Realtime + RPC + Edge Functions)** on the backend.
No traditional Node backend. All critical operations are transactional PostgreSQL functions.

## Core principles implemented

| Rule | Where it is enforced |
|---|---|
| One role per user (`client` / `driver` / `admin`), never self-assignable | `handle_new_user` + `guard_profile_update` triggers, `admin_set_role` RPC |
| Unverified driver cannot create/publish a trip | `app.assert_driver_verified()` inside `create_trip` / `publish_trip` |
| One driver = one vehicle | `vehicles.driver_id UNIQUE` |
| Trip needs ≥ 2 checkpoints, ordered | `create_trip`, `UNIQUE(trip_id, sequence)` |
| Distance / ETA / reference prices computed by the system | `create_trip` (PostGIS `ST_Distance`) + `app.reference_price()` |
| Segment pricing, booking price = sum of covered segments | `app.segment_price_sum()` |
| Atomic seat reservation across **every** covered segment | `app.move_seats()` with `SELECT … FOR UPDATE` |
| No overbooking | `reserved_seats <= capacity` CHECK + locked update |
| Approval-only booking: no payment step; driver or admin approves (auto-confirm trips confirm instantly) | `create_booking` / `confirm_booking` / `reject_booking` |
| Booking price immutable after confirmation | `guard_booking_price` trigger |
| Cancellation allowed until 24 h before departure (non-monetary rule) | `cancellation_quote` / `cancel_booking` |
| Partial resale, price ceiling, auto-closing listing, atomic locking | `create_resale` / `buy_resale` |
| Transfer keeps booking identity **and** price | `approve_transfer` |
| Resale and transfer are mutually exclusive | checks in `create_resale` / `request_transfer` |
| Direction-aware route matching with geographic tolerance | `search_trips` (PostGIS `ST_DWithin`, `a.sequence < b.sequence`) |
| Everything audited | `app.audit()` calls across all sensitive RPCs |

## Project layout

```
src/
├── app/              App shell + design-system stylesheet
├── router/           Lazy-loaded routes + role guards
├── stores/           Pinia: auth, locale, notifications (shared state only)
├── composables/      useAsync (loading/success/empty/error), toast, geolocation, debounce
├── components/       Reusable UI (AsyncSection, DataTable, PlaceAutocomplete, MapView…)
├── layouts/          AppLayout (bottom nav on mobile), AuthLayout
├── pages/            Home, 404
├── features/         auth · profile · trips · bookings · resale · transfers ·
│                     notifications · ratings · admin
├── services/
│   ├── supabase/     client (anon key only) + typed rpc/query helpers
│   ├── maps/         MapProvider abstraction (OSM default, Google adapter)
│   └── domain/       tripService, bookingService, resaleService,
│                     transferService, notificationService, profileService, adminService
├── domain/rules.ts   Pure business rules mirrored from SQL (unit-tested)
├── i18n/             ar / fr / en + RTL handling
├── types/            Database entities, RPC payloads, typed AppError
└── utils/
supabase/
├── migrations/0001…0019   ordered, deterministic
├── functions/payments     Unused since approval-only flow (kept for later removal)
├── functions/expire-bookings
├── seed_dev.sql           demo users / verified driver / published trip
└── config.toml
tests/                      Vitest unit tests + SQL integration tests
```

## Documentation

- [LINE Mini App MVP Plan](LINE_MINI_APP_MVP_PLAN.md)
- [Deployment Guide](DEPLOYMENT_GUIDE.md)
- [Local Setup Guide](LOCAL_SETUP_GUIDE.md)

## Setup

```bash
npm install
cp .env.example .env     # fill VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
```

### Database

```bash
supabase start                 # local stack (or use a hosted project)
supabase db reset              # applies supabase/migrations/* in order
psql "$SUPABASE_DB_URL" -f supabase/seed_dev.sql    # demo data (dev only)
```

Hosted project:

```bash
supabase link --project-ref <ref>
supabase db push
supabase functions deploy expire-bookings
supabase secrets set SUPABASE_SERVICE_ROLE_KEY=<service-role>  # server-side only
```

Schedule `expire-bookings` every 5 minutes (pg_cron or Supabase scheduler) so unanswered
driver-approval bookings release their seats.

### Run

```bash
npm run dev        # http://localhost:5173
npm run build      # typecheck (vue-tsc) + production bundle
npm run preview
npm test           # Vitest business-rule suite
```

### Demo accounts (seed, password `Passw0rd!`)

| Email | Role |
|---|---|
| `client@demo.test` | client (verified identity) |
| `client2@demo.test` | client (resale buyer) |
| `driver@demo.test` | verified driver + vehicle + published Alger→Laghouat trip |
| `admin@demo.test` | admin |

## Admin bootstrapping

Public signup can only request `client` or `driver`. The first admin is created server-side
(`seed_dev.sql`, or `update public.profiles set role='admin' where id=…` with the service role).
Afterwards admins promote users through the audited `admin_set_role` RPC.

## Security model

* RLS enabled on every user-facing table; policies in `0015_rls.sql`.
* Role, identity status, payment status, seat inventory and prices are **server-side only**.
* `verification-documents` bucket is private; the admin UI opens documents via short-lived signed URLs.
* Only the public anon key ships to the browser. Service-role keys and PSP secrets live in Edge Function secrets.
* Raw database errors never reach the UI — they are mapped to typed `AppError` codes with i18n messages.

## Configuration (DB `settings` table, editable in the admin UI)

`booking_approval_timeout_minutes` (30) · `payment_timeout_minutes` · `resale_payment_timeout_minutes` ·
`cancellation_window_hours` (24) · `cancellation_min_minutes_after_booking` (30, unused) · `refund_percentage` (80, unused) ·
`price_base_dzd` · `price_per_km_dzd` · `price_rounding_dzd` · `search_tolerance_meters` · `average_speed_kmh` ·
`allow_mock_payments` (set to `false` in production) · `payment_provider`.

## Testing

* `npm test` — 29 unit tests: pricing, segment derivation, route direction, bottleneck seat
  availability, overbooking refusal, partial resale + listing closure,
  transfer price preservation, resale/transfer exclusivity, error mapping, i18n completeness.
* `tests/sql/business_rules.test.sql` — integration tests against a live database:
  atomic multi-segment reservation, overbooking rejection, auto-confirm without payment,
  price immutability, resale ceiling + inventory conservation, cancellation eligibility.

## Deliberately out of MVP scope

Workflow/graph execution engine, chat, continuous GPS tracking, multi-vehicle drivers,
multi-role users, accounting/settlement engine, loyalty, corporate accounts. Business
operations are nonetheless modelled as discrete, fact-oriented RPCs (`create_booking`,
`pay_booking`, `confirm_booking`, `cancel_booking`, `create_resale`, `buy_resale`,
`request_transfer`, `approve_transfer`, `reject_transfer`, `start_trip`, `complete_trip`)
so they can later become graph nodes without redesign.
