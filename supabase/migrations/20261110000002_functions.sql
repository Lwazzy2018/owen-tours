-- =====================================================================
-- Functions and triggers
-- =====================================================================

-- Keep updated_at current on every update.
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

do $$
declare t text;
begin
  foreach t in array array['profiles', 'company_settings', 'trips', 'departures', 'specials',
                           'bookings', 'past_trips', 'enquiries']
  loop
    execute format(
      'create trigger %I before update on public.%I for each row execute function public.set_updated_at()',
      t || '_set_updated_at', t);
  end loop;
end;
$$;

-- Create a profile automatically when someone signs up with Supabase Auth.
-- Everyone starts as a customer; admins are promoted by another admin.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, phone, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.raw_user_meta_data ->> 'phone',
    'customer'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Is the signed-in user an admin? Used by RLS policies.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.role = 'admin'
  );
$$;

-- Customers may edit their own name and phone, but never their role.
-- Server connections (no signed-in user, e.g. the ASP.NET API) and admins may.
create or replace function public.protect_profile_role()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.role is distinct from old.role
     and auth.uid() is not null
     and not public.is_admin() then
    raise exception 'Only an admin can change a user''s role'
      using errcode = '42501';
  end if;
  return new;
end;
$$;

create trigger profiles_protect_role
  before update on public.profiles
  for each row execute function public.protect_profile_role();

-- ---------------------------------------------------------------------
-- Seat reservation. Atomic: two people can never take the same last seat.
-- Returns true if the seats were reserved, false if not enough are left.
-- Only the API (service role) may call these.
-- ---------------------------------------------------------------------
create or replace function public.reserve_seats(p_departure_id uuid, p_seats int)
returns boolean
language plpgsql
as $$
declare
  affected int;
begin
  if p_seats is null or p_seats < 1 then
    raise exception 'Seats must be at least 1';
  end if;

  update public.departures
     set seats_booked = seats_booked + p_seats
   where id = p_departure_id
     and not is_cancelled_by_company
     and seats_booked + p_seats <= capacity;

  get diagnostics affected = row_count;
  return affected = 1;
end;
$$;

create or replace function public.release_seats(p_departure_id uuid, p_seats int)
returns void
language plpgsql
as $$
begin
  update public.departures
     set seats_booked = greatest(seats_booked - p_seats, 0)
   where id = p_departure_id;
end;
$$;

revoke all on function public.reserve_seats(uuid, int) from public, anon, authenticated;
revoke all on function public.release_seats(uuid, int) from public, anon, authenticated;
grant execute on function public.reserve_seats(uuid, int) to service_role;
grant execute on function public.release_seats(uuid, int) to service_role;

-- Distinct departure provinces and areas with upcoming trips, for the search filters.
create or replace view public.departure_locations
with (security_invoker = true)
as
select distinct d.departure_province, d.departure_area
from public.departures d
join public.trips t on t.id = d.trip_id
where t.is_published
  and not d.is_cancelled_by_company
  and d.departure_at > now();

-- Live "seats left" updates in the app (Supabase Realtime).
alter publication supabase_realtime add table public.departures;
