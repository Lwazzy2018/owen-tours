-- =====================================================================
-- Row Level Security
-- The Flutter app talks to Supabase directly only to READ public data
-- (and for Realtime). Every booking, payment and admin write goes
-- through the ASP.NET API, which connects with a server role that
-- bypasses RLS. These policies are the safety net.
-- =====================================================================

alter table public.profiles          enable row level security;
alter table public.company_settings  enable row level security;
alter table public.trips             enable row level security;
alter table public.trip_images       enable row level security;
alter table public.itinerary_days    enable row level security;
alter table public.departures        enable row level security;
alter table public.specials          enable row level security;
alter table public.special_trips     enable row level security;
alter table public.bookings          enable row level security;
alter table public.travellers        enable row level security;
alter table public.guardian_details  enable row level security;
alter table public.booking_discounts enable row level security;
alter table public.instalments       enable row level security;
alter table public.payments          enable row level security;
alter table public.reviews           enable row level security;
alter table public.past_trips        enable row level security;
alter table public.past_trip_media   enable row level security;
alter table public.testimonials      enable row level security;
alter table public.enquiries         enable row level security;
alter table public.notifications     enable row level security;
alter table public.audit_log         enable row level security;

-- Helper: does the signed-in user own this booking?
create or replace function public.owns_booking(p_booking_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.bookings b
    where b.id = p_booking_id and b.customer_id = auth.uid()
  );
$$;

-- ---------------- Profiles ----------------
create policy profiles_select_own_or_admin on public.profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

create policy profiles_update_own on public.profiles
  for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- ---------------- Company settings ----------------
create policy company_settings_read on public.company_settings
  for select to anon, authenticated using (true);

create policy company_settings_admin_write on public.company_settings
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------- Trips and their content ----------------
create policy trips_read on public.trips
  for select to anon, authenticated
  using (is_published or public.is_admin());

create policy trips_admin_write on public.trips
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy trip_images_read on public.trip_images
  for select to anon, authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id and (t.is_published or public.is_admin())));

create policy trip_images_admin_write on public.trip_images
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy itinerary_days_read on public.itinerary_days
  for select to anon, authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id and (t.is_published or public.is_admin())));

create policy itinerary_days_admin_write on public.itinerary_days
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy departures_read on public.departures
  for select to anon, authenticated
  using (exists (select 1 from public.trips t where t.id = trip_id and (t.is_published or public.is_admin())));

create policy departures_admin_write on public.departures
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------- Specials ----------------
-- Private promo codes are hidden from customers (they must type the code).
create policy specials_read on public.specials
  for select to anon, authenticated
  using (
    public.is_admin()
    or (is_active and now() between starts_at and ends_at and (type <> 'promo_code' or is_public))
  );

create policy specials_admin_write on public.specials
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy special_trips_read on public.special_trips
  for select to anon, authenticated using (true);

create policy special_trips_admin_write on public.special_trips
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------- Bookings and everything attached ----------------
-- Read-only for customers (own rows). No insert/update policies: the API writes.
create policy bookings_read_own on public.bookings
  for select to authenticated
  using (customer_id = auth.uid() or public.is_admin());

create policy travellers_read_own on public.travellers
  for select to authenticated
  using (public.owns_booking(booking_id) or public.is_admin());

create policy guardian_details_read_own on public.guardian_details
  for select to authenticated
  using (public.owns_booking(booking_id) or public.is_admin());

create policy booking_discounts_read_own on public.booking_discounts
  for select to authenticated
  using (public.owns_booking(booking_id) or public.is_admin());

create policy instalments_read_own on public.instalments
  for select to authenticated
  using (public.owns_booking(booking_id) or public.is_admin());

create policy payments_read_own on public.payments
  for select to authenticated
  using (public.owns_booking(booking_id) or public.is_admin());

-- ---------------- Reviews ----------------
create policy reviews_read on public.reviews
  for select to anon, authenticated using (true);

-- ---------------- Past trips ----------------
create policy past_trips_read on public.past_trips
  for select to anon, authenticated
  using (is_published or public.is_admin());

create policy past_trips_admin_write on public.past_trips
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy past_trip_media_read on public.past_trip_media
  for select to anon, authenticated
  using (exists (select 1 from public.past_trips p where p.id = past_trip_id and (p.is_published or public.is_admin())));

create policy past_trip_media_admin_write on public.past_trip_media
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

create policy testimonials_read on public.testimonials
  for select to anon, authenticated
  using (
    public.is_admin()
    or (is_published and exists (select 1 from public.past_trips p where p.id = past_trip_id and p.is_published))
  );

create policy testimonials_admin_write on public.testimonials
  for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------- Enquiries ----------------
-- Anyone may send an enquiry (the API rate-limits it). Only admins see all of them.
create policy enquiries_insert on public.enquiries
  for insert to anon, authenticated
  with check (
    status = 'new' and staff_notes is null
    and (customer_id is null or customer_id = auth.uid())
  );

create policy enquiries_read_own_or_admin on public.enquiries
  for select to authenticated
  using (customer_id = auth.uid() or public.is_admin());

create policy enquiries_admin_update on public.enquiries
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------------- Notifications and audit log ----------------
create policy notifications_read_own on public.notifications
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy audit_log_admin_read on public.audit_log
  for select to authenticated
  using (public.is_admin());

-- ---------------- Table privileges ----------------
-- RLS decides which rows; these grants decide which operations are possible at all.
revoke all on all tables in schema public from anon, authenticated;

grant select on public.company_settings, public.trips, public.trip_images, public.itinerary_days,
                public.departures, public.specials, public.special_trips, public.reviews,
                public.past_trips, public.past_trip_media, public.testimonials,
                public.departure_locations
  to anon, authenticated;

grant select on public.profiles, public.bookings, public.travellers, public.guardian_details,
                public.booking_discounts, public.instalments, public.payments,
                public.enquiries, public.notifications, public.audit_log
  to authenticated;

grant update (full_name, phone) on public.profiles to authenticated;
grant update on public.company_settings to authenticated;
grant insert, update, delete on public.trips, public.trip_images, public.itinerary_days,
                                public.departures, public.specials, public.special_trips,
                                public.past_trips, public.past_trip_media, public.testimonials
  to authenticated;
grant insert (customer_id, name, phone, email, services, destination, travel_from, travel_to,
              people, budget_cents, message)
  on public.enquiries to anon, authenticated;
grant update (status, staff_notes) on public.enquiries to authenticated;
