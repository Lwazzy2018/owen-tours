-- =====================================================================
-- Owen Tours and Travel – database schema
-- Money is always stored as integer cents. Timestamps are stored in UTC
-- (timestamptz) and shown in South African time (Africa/Johannesburg).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------
-- Profiles (one row per Supabase auth user)
-- ---------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  full_name   text not null default '',
  phone       text,
  role        text not null default 'customer' check (role in ('admin', 'customer')),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Company settings (exactly one row)
-- ---------------------------------------------------------------------
create table public.company_settings (
  id               int primary key default 1 check (id = 1),
  company_name     text not null,
  registered_name  text,
  tagline          text,
  phone            text,
  whatsapp         text,
  email            text,
  address          text,
  facebook_url     text,
  instagram_url    text,
  tiktok_url       text,
  about_text       text,
  updated_at       timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Trips
-- ---------------------------------------------------------------------
create table public.trips (
  id                      uuid primary key default gen_random_uuid(),
  title                   text not null check (length(trim(title)) > 0),
  destination             text not null,
  destination_country     text not null default 'South Africa',
  is_cross_border         boolean generated always as (destination_country <> 'South Africa') stored,
  category                text not null check (category in (
                            'beach', 'weekend_getaway', 'hiking', 'snow', 'city',
                            'safari', 'cross_border', 'youth_camp', 'day_trip', 'other')),
  audience                text not null default 'everyone'
                            check (audience in ('everyone', 'adults_only', 'high_school')),
  min_grade               int check (min_grade between 1 and 12),
  max_grade               int check (max_grade between 1 and 12),
  activities              text[] not null default '{}',
  tagline                 text,
  description             text not null default '',
  cover_image_url         text,

  transport_included      boolean not null default false,
  transport_type          text check (transport_type in ('bus', 'coach', 'minibus', 'flight', 'other')),
  transport_notes         text,

  meals_breakfast         boolean not null default false,
  meals_lunch             boolean not null default false,
  meals_dinner            boolean not null default false,
  meals_snacks            boolean not null default false,
  meals_notes             text,

  accommodation_included  boolean not null default false,
  accommodation_type      text check (accommodation_type in ('hotel', 'lodge', 'guesthouse', 'camping', 'other')),
  accommodation_notes     text,

  includes                text[] not null default '{}',   -- other extras included
  excludes                text[] not null default '{}',   -- what is NOT included
  is_published            boolean not null default false,
  created_at              timestamptz not null default now(),
  updated_at              timestamptz not null default now(),

  -- High school trips need a grade range; other trips must not have one.
  constraint trips_grade_range check (
    (audience = 'high_school' and min_grade is not null and max_grade is not null and min_grade <= max_grade)
    or (audience <> 'high_school' and min_grade is null and max_grade is null)
  ),
  constraint trips_transport_type check (transport_included or transport_type is null),
  constraint trips_accommodation_type check (accommodation_included or accommodation_type is null)
);

create table public.trip_images (
  id             uuid primary key default gen_random_uuid(),
  trip_id        uuid not null references public.trips (id) on delete cascade,
  url            text not null,
  thumbnail_url  text,
  storage_path   text,
  sort_order     int not null default 0,
  created_at     timestamptz not null default now()
);

create table public.itinerary_days (
  id           uuid primary key default gen_random_uuid(),
  trip_id      uuid not null references public.trips (id) on delete cascade,
  day_number   int not null check (day_number >= 1),
  title        text not null,
  description  text not null default '',
  unique (trip_id, day_number)
);

-- ---------------------------------------------------------------------
-- Departures (one trip can run on several dates)
-- ---------------------------------------------------------------------
create table public.departures (
  id                     uuid primary key default gen_random_uuid(),
  trip_id                uuid not null references public.trips (id) on delete restrict,
  departure_province     text not null check (departure_province in (
                           'Eastern Cape', 'Free State', 'Gauteng', 'KwaZulu-Natal', 'Limpopo',
                           'Mpumalanga', 'North West', 'Northern Cape', 'Western Cape')),
  departure_area         text not null check (length(trim(departure_area)) > 0),
  meeting_place          text not null,
  departure_at           timestamptz not null,
  return_date            date not null,
  capacity               int not null check (capacity > 0),
  seats_booked           int not null default 0,
  adult_price_cents      int not null check (adult_price_cents >= 0),
  child_price_cents      int not null check (child_price_cents >= 0),
  booking_deadline       timestamptz not null,
  allow_instalments      boolean not null default false,
  deposit_cents          int not null default 0 check (deposit_cents >= 0),
  final_payment_due      date,

  is_cancellable         boolean not null default true,
  cancellation_deadline  timestamptz,
  refund_type            text not null default 'none' check (refund_type in ('full', 'partial', 'none')),
  refund_percent         int check (refund_percent between 0 and 100),
  deposit_refundable     boolean not null default false,
  cancellation_notes     text,

  is_cancelled_by_company boolean not null default false,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),

  -- The database itself refuses to overbook, even if the API has a bug.
  constraint departures_seats check (seats_booked >= 0 and seats_booked <= capacity),
  constraint departures_booking_deadline check (booking_deadline <= departure_at),
  constraint departures_cancellation_deadline check (
    (not is_cancellable)
    or (cancellation_deadline is not null and cancellation_deadline < departure_at)
  ),
  constraint departures_partial_refund check (
    refund_type <> 'partial' or (refund_percent is not null and refund_percent between 1 and 99)
  ),
  constraint departures_instalments check (
    (not allow_instalments) or (final_payment_due is not null and deposit_cents > 0)
  )
);

-- ---------------------------------------------------------------------
-- Specials and discounts
-- ---------------------------------------------------------------------
create table public.specials (
  id                uuid primary key default gen_random_uuid(),
  name              text not null,
  description       text,
  type              text not null check (type in ('percentage', 'student', 'group', 'promo_code')),
  percent_off       int not null check (percent_off between 1 and 100),
  min_travellers    int check (min_travellers >= 2),
  promo_code        text,
  is_public         boolean not null default true,
  max_uses          int check (max_uses > 0),
  times_used        int not null default 0 check (times_used >= 0),
  starts_at         timestamptz not null,
  ends_at           timestamptz not null,
  is_active         boolean not null default true,
  banner_image_url  text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint specials_dates check (starts_at < ends_at),
  constraint specials_group check (type <> 'group' or min_travellers is not null),
  constraint specials_promo check ((type = 'promo_code') = (promo_code is not null)),
  constraint specials_max_uses check (max_uses is null or times_used <= max_uses)
);
-- Promo codes are case-insensitive and unique.
create unique index specials_promo_code_unique on public.specials (lower(promo_code)) where promo_code is not null;

create table public.special_trips (
  special_id  uuid not null references public.specials (id) on delete cascade,
  trip_id     uuid not null references public.trips (id) on delete cascade,
  primary key (special_id, trip_id)
);

-- ---------------------------------------------------------------------
-- Bookings
-- ---------------------------------------------------------------------
create sequence public.booking_reference_seq start 1001;

create table public.bookings (
  id                            uuid primary key default gen_random_uuid(),
  reference                     text not null unique
                                  default ('OT' || lpad(nextval('public.booking_reference_seq')::text, 6, '0')),
  departure_id                  uuid not null references public.departures (id) on delete restrict,
  customer_id                   uuid not null references public.profiles (id) on delete restrict,
  status                        text not null default 'pending'
                                  check (status in ('pending', 'confirmed', 'paid', 'cancelled', 'expired')),
  payment_plan                  text not null check (payment_plan in ('full', 'instalments')),
  adults                        int not null check (adults >= 0),
  children                      int not null check (children >= 0),
  subtotal_cents                int not null check (subtotal_cents >= 0),
  discount_cents                int not null default 0 check (discount_cents >= 0),
  total_cents                   int not null check (total_cents >= 0),
  deposit_cents                 int not null default 0 check (deposit_cents >= 0),
  amount_paid_cents             int not null default 0 check (amount_paid_cents >= 0),
  expires_at                    timestamptz,
  cancellation_policy_snapshot  jsonb not null,
  policy_accepted_at            timestamptz not null,
  cancelled_at                  timestamptz,
  cancelled_by                  uuid references public.profiles (id),
  cancellation_reason           text,
  refund_cents                  int not null default 0 check (refund_cents >= 0),
  refund_status                 text not null default 'none' check (refund_status in ('none', 'pending', 'refunded')),
  refunded_at                   timestamptz,
  created_at                    timestamptz not null default now(),
  updated_at                    timestamptz not null default now(),
  constraint bookings_travellers check (adults + children >= 1),
  constraint bookings_total check (total_cents = subtotal_cents - discount_cents),
  constraint bookings_pending_expiry check (status <> 'pending' or expires_at is not null)
);

create table public.travellers (
  id               uuid primary key default gen_random_uuid(),
  booking_id       uuid not null references public.bookings (id) on delete cascade,
  full_name        text not null check (length(trim(full_name)) > 0),
  id_number        text,
  passport_number  text,
  passport_expiry  date,
  phone            text,
  is_child         boolean not null default false,
  date_of_birth    date,
  school_grade     int check (school_grade between 1 and 12),
  medical_notes    text,
  allergies        text,
  created_at       timestamptz not null default now(),
  constraint travellers_identity check (id_number is not null or passport_number is not null)
);

create table public.guardian_details (
  id                       uuid primary key default gen_random_uuid(),
  booking_id               uuid not null unique references public.bookings (id) on delete cascade,
  guardian_name            text not null,
  guardian_phone           text not null,
  guardian_relationship    text not null,
  emergency_contact_name   text not null,
  emergency_contact_phone  text not null,
  consent_given_at         timestamptz not null
);

create table public.booking_discounts (
  id                     uuid primary key default gen_random_uuid(),
  booking_id             uuid not null unique references public.bookings (id) on delete cascade,
  special_id             uuid not null references public.specials (id) on delete restrict,
  special_name           text not null,           -- snapshot, so renaming a special changes nothing
  percent_off            int not null,            -- snapshot
  discount_cents         int not null check (discount_cents >= 0),
  status                 text not null check (status in ('applied', 'pending_verification', 'rejected')),
  student_id_image_path  text,                    -- private bucket path, never a public URL
  reviewed_by            uuid references public.profiles (id),
  reviewed_at            timestamptz,
  review_note            text,
  promo_use_released     boolean not null default false,
  created_at             timestamptz not null default now()
);

create table public.instalments (
  id                uuid primary key default gen_random_uuid(),
  booking_id        uuid not null references public.bookings (id) on delete cascade,
  sequence          int not null check (sequence >= 1),
  due_date          date not null,
  amount_cents      int not null check (amount_cents > 0),
  status            text not null default 'due' check (status in ('due', 'paid', 'overdue', 'cancelled')),
  paid_at           timestamptz,
  unique (booking_id, sequence)
);

create table public.payments (
  id                  uuid primary key default gen_random_uuid(),
  booking_id          uuid not null references public.bookings (id) on delete restrict,
  purpose             text not null check (purpose in ('full', 'deposit', 'instalment', 'balance')),
  instalment_id       uuid references public.instalments (id),
  amount_cents        int not null check (amount_cents > 0),
  provider            text not null default 'payfast',
  provider_reference  text unique,                 -- e.g. PayFast pf_payment_id; unique = idempotent
  status              text not null default 'pending' check (status in ('pending', 'complete', 'failed', 'cancelled')),
  paid_at             timestamptz,
  raw_payload         jsonb,
  created_at          timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Reviews, past trips, testimonials
-- ---------------------------------------------------------------------
create table public.reviews (
  id           uuid primary key default gen_random_uuid(),
  trip_id      uuid not null references public.trips (id) on delete cascade,
  customer_id  uuid not null references public.profiles (id) on delete cascade,
  rating       int not null check (rating between 1 and 5),
  comment      text,
  created_at   timestamptz not null default now(),
  unique (trip_id, customer_id)
);

create table public.past_trips (
  id               uuid primary key default gen_random_uuid(),
  trip_id          uuid references public.trips (id) on delete set null,
  title            text not null,
  destination      text not null,
  travelled_on     date not null,
  traveller_count  int check (traveller_count >= 0),
  story            text,
  cover_url        text,
  is_featured      boolean not null default false,
  is_published     boolean not null default false,
  sort_order       int not null default 0,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table public.past_trip_media (
  id             uuid primary key default gen_random_uuid(),
  past_trip_id   uuid not null references public.past_trips (id) on delete cascade,
  media_type     text not null check (media_type in ('image', 'video')),
  url            text not null,
  thumbnail_url  text,
  storage_path   text,
  caption        text,
  sort_order     int not null default 0,
  created_at     timestamptz not null default now()
);

create table public.testimonials (
  id             uuid primary key default gen_random_uuid(),
  past_trip_id   uuid not null references public.past_trips (id) on delete cascade,
  customer_name  text not null,
  quote          text not null,
  rating         int check (rating between 1 and 5),
  photo_url      text,
  is_published   boolean not null default false,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Enquiries ("Plan a trip with us" / free consultation)
-- ---------------------------------------------------------------------
create table public.enquiries (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid references public.profiles (id) on delete set null,
  name          text not null,
  phone         text not null,
  email         text,
  services      text[] not null default '{}' check (services <@ array[
                  'flights', 'accommodation', 'tour_package', 'visa', 'travel_insurance', 'consultation']::text[]),
  destination   text,
  travel_from   date,
  travel_to     date,
  people        int check (people >= 1),
  budget_cents  int check (budget_cents >= 0),
  message       text,
  status        text not null default 'new' check (status in ('new', 'contacted', 'quoted', 'closed')),
  staff_notes   text,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Notifications (log of everything sent) and audit log
-- ---------------------------------------------------------------------
create table public.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references public.profiles (id) on delete set null,
  booking_id  uuid references public.bookings (id) on delete cascade,
  channel     text not null default 'email' check (channel in ('email', 'sms', 'whatsapp', 'push', 'log')),
  template    text not null,
  subject     text,
  body        text not null,
  dedupe_key  text unique,     -- guarantees a reminder is never sent twice
  sent_at     timestamptz not null default now()
);

create table public.audit_log (
  id          bigint generated always as identity primary key,
  actor_id    uuid,
  action      text not null,
  entity      text not null,
  entity_id   text,
  data        jsonb,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------
create index trips_published_idx           on public.trips (is_published, category);
create index trip_images_trip_idx          on public.trip_images (trip_id, sort_order);
create index departures_trip_idx           on public.departures (trip_id, departure_at);
create index departures_location_idx       on public.departures (departure_province, departure_area);
create index departures_departure_at_idx   on public.departures (departure_at);
create index bookings_customer_idx         on public.bookings (customer_id, created_at desc);
create index bookings_departure_idx        on public.bookings (departure_id, status);
create index bookings_pending_expiry_idx   on public.bookings (expires_at) where status = 'pending';
create index travellers_booking_idx        on public.travellers (booking_id);
create index instalments_due_idx           on public.instalments (due_date) where status in ('due', 'overdue');
create index payments_booking_idx          on public.payments (booking_id);
create index past_trips_published_idx      on public.past_trips (is_published, is_featured desc, sort_order);
create index past_trip_media_idx           on public.past_trip_media (past_trip_id, sort_order);
create index testimonials_past_trip_idx    on public.testimonials (past_trip_id);
create index specials_active_idx           on public.specials (is_active, starts_at, ends_at);
create index enquiries_status_idx          on public.enquiries (status, created_at desc);
create index audit_log_entity_idx          on public.audit_log (entity, entity_id);
create index reviews_trip_idx              on public.reviews (trip_id);
