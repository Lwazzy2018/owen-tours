-- Security tests: run after migrations + seed on a test database.
-- Every check raises an exception if it fails, so the script stops on the first problem.
\set ON_ERROR_STOP on

-- Test users (the trigger creates their profiles)
insert into auth.users (id, email, raw_user_meta_data) values
  ('aaaaaaaa-0000-4000-8000-000000000001', 'admin@test.local', '{"full_name":"Test Admin"}'),
  ('aaaaaaaa-0000-4000-8000-000000000002', 'thandi@test.local', '{"full_name":"Thandi Customer","phone":"0820000002"}'),
  ('aaaaaaaa-0000-4000-8000-000000000003', 'sipho@test.local', '{"full_name":"Sipho Customer"}');
update public.profiles set role = 'admin' where id = 'aaaaaaaa-0000-4000-8000-000000000001';

-- An unpublished trip, a booking for Thandi, and a private promo code
insert into public.trips (id, title, destination, category, is_published)
values ('11111111-0000-4000-8000-0000000000ff', 'Draft trip', 'Nowhere', 'other', false);

insert into public.bookings (id, departure_id, customer_id, status, payment_plan, adults, children,
                             subtotal_cents, discount_cents, total_cents, expires_at,
                             cancellation_policy_snapshot, policy_accepted_at)
values ('bbbbbbbb-0000-4000-8000-000000000001', '22222222-0000-4000-8000-000000000005',
        'aaaaaaaa-0000-4000-8000-000000000002', 'pending', 'full', 2, 0, 180000, 0, 180000,
        now() + interval '20 minutes', '{}'::jsonb, now());
insert into public.travellers (booking_id, full_name, id_number)
values ('bbbbbbbb-0000-4000-8000-000000000001', 'Thandi Customer', '9001015009087');

-- Helper to act as a user
create or replace function pg_temp.act_as(p_role text, p_user uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', coalesce(p_user::text, ''), false);
  execute format('set role %I', p_role);
end $$;

-- 1. Guests see published trips only
select pg_temp.act_as('anon', null);
do $$ begin
  if (select count(*) from public.trips) <> 6 then raise exception 'FAIL: anon should see 6 published trips'; end if;
  if exists (select 1 from public.trips where not is_published) then raise exception 'FAIL: anon sees a draft trip'; end if;
  if (select count(*) from public.departures) <> 8 then raise exception 'FAIL: anon should see 8 departures'; end if;
end $$;

-- 2. Guests cannot see bookings at all
do $$ begin
  begin
    perform count(*) from public.bookings;
    raise exception 'FAIL: anon could query bookings';
  exception when insufficient_privilege then null;
  end;
end $$;

-- 3. Guests see public specials but not the private promo code
do $$ begin
  if exists (select 1 from public.specials where promo_code is not null) then
    raise exception 'FAIL: anon can see a private promo code';
  end if;
end $$;

-- 4. Guests can send an enquiry but cannot read enquiries
insert into public.enquiries (name, phone, services, message)
values ('Guest', '0820000000', array['visa'], 'Need help with a visa');
do $$ begin
  begin
    perform count(*) from public.enquiries;
    raise exception 'FAIL: anon could read enquiries';
  exception when insufficient_privilege then null;
  end;
end $$;

-- 5. Guests cannot change trips
do $$ begin
  begin
    update public.trips set title = 'Hacked';
    raise exception 'FAIL: anon could update trips';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- 6. Thandi sees her own booking; Sipho does not
select pg_temp.act_as('authenticated', 'aaaaaaaa-0000-4000-8000-000000000002');
do $$ begin
  if (select count(*) from public.bookings) <> 1 then raise exception 'FAIL: Thandi should see her 1 booking'; end if;
  if (select count(*) from public.travellers) <> 1 then raise exception 'FAIL: Thandi should see her traveller'; end if;
end $$;
reset role;

select pg_temp.act_as('authenticated', 'aaaaaaaa-0000-4000-8000-000000000003');
do $$ begin
  if (select count(*) from public.bookings) <> 0 then raise exception 'FAIL: Sipho can see someone else''s booking'; end if;
  if (select count(*) from public.travellers) <> 0 then raise exception 'FAIL: Sipho can see someone else''s traveller'; end if;
  if (select count(*) from public.profiles) <> 1 then raise exception 'FAIL: Sipho can see other profiles'; end if;
end $$;

-- 7. A customer cannot create or change bookings directly
do $$ begin
  begin
    update public.bookings set status = 'paid';
    raise exception 'FAIL: customer could update a booking';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.bookings (departure_id, customer_id, payment_plan, adults, children, subtotal_cents,
                                 total_cents, expires_at, cancellation_policy_snapshot, policy_accepted_at)
    values ('22222222-0000-4000-8000-000000000005', 'aaaaaaaa-0000-4000-8000-000000000003', 'full', 1, 0, 0, 0,
            now(), '{}', now());
    raise exception 'FAIL: customer could insert a booking';
  exception when insufficient_privilege then null;
  end;
end $$;

-- 8. A customer cannot make themselves admin
do $$ begin
  begin
    update public.profiles set role = 'admin' where id = auth.uid();
    raise exception 'FAIL: customer changed their own role';
  exception when insufficient_privilege then null;
  end;
end $$;

-- 9. A customer can update their own name
update public.profiles set full_name = 'Sipho M' where id = auth.uid();
do $$ begin
  if (select full_name from public.profiles where id = auth.uid()) <> 'Sipho M' then
    raise exception 'FAIL: customer could not update own name';
  end if;
end $$;

-- 10. A customer cannot call the seat reservation function
do $$ begin
  begin
    perform public.reserve_seats('22222222-0000-4000-8000-000000000005', 1);
    raise exception 'FAIL: customer could reserve seats directly';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- 11. Admin sees everything, including drafts, all bookings and enquiries
select pg_temp.act_as('authenticated', 'aaaaaaaa-0000-4000-8000-000000000001');
do $$ begin
  if (select count(*) from public.trips) <> 7 then raise exception 'FAIL: admin should see 7 trips incl. draft'; end if;
  if (select count(*) from public.bookings) <> 1 then raise exception 'FAIL: admin should see all bookings'; end if;
  if (select count(*) from public.enquiries) <> 1 then raise exception 'FAIL: admin should see enquiries'; end if;
  if not exists (select 1 from public.specials where promo_code = 'TEST10') then raise exception 'FAIL: admin should see promo codes'; end if;
end $$;
update public.trips set title = 'Draft trip (edited)' where id = '11111111-0000-4000-8000-0000000000ff';
reset role;

-- 12. Database constraints catch bad data even if the API has a bug
do $$ begin
  begin
    update public.departures set seats_booked = capacity + 1 where id = '22222222-0000-4000-8000-000000000005';
    raise exception 'FAIL: overbooking constraint missing';
  exception when check_violation then null;
  end;
  begin
    update public.departures set is_cancellable = true, cancellation_deadline = null
    where id = '22222222-0000-4000-8000-000000000005';
    raise exception 'FAIL: cancellable departure without deadline accepted';
  exception when check_violation then null;
  end;
  begin
    update public.departures set refund_type = 'partial', refund_percent = null
    where id = '22222222-0000-4000-8000-000000000005';
    raise exception 'FAIL: partial refund without percent accepted';
  exception when check_violation then null;
  end;
  begin
    update public.bookings set total_cents = 1 where id = 'bbbbbbbb-0000-4000-8000-000000000001';
    raise exception 'FAIL: booking total not checked against subtotal - discount';
  exception when check_violation then null;
  end;
  begin
    insert into public.trips (title, destination, category, audience) values ('Camp', 'X', 'youth_camp', 'high_school');
    raise exception 'FAIL: high school trip without grade range accepted';
  exception when check_violation then null;
  end;
  begin
    insert into public.specials (name, type, percent_off, promo_code, starts_at, ends_at)
    values ('Dup', 'promo_code', 5, 'test10', now(), now() + interval '1 day');
    raise exception 'FAIL: duplicate promo code (different case) accepted';
  exception when unique_violation then null;
  end;
end $$;

-- 13. Seat reservation works and refuses when full
do $$
declare ok boolean;
begin
  update public.departures set seats_booked = 0 where id = '22222222-0000-4000-8000-000000000005';
  ok := public.reserve_seats('22222222-0000-4000-8000-000000000005', 14);
  if not ok then raise exception 'FAIL: could not reserve 14 of 14 seats'; end if;
  ok := public.reserve_seats('22222222-0000-4000-8000-000000000005', 1);
  if ok then raise exception 'FAIL: reserved a 15th seat on a 14-seat departure'; end if;
  perform public.release_seats('22222222-0000-4000-8000-000000000005', 14);
  if (select seats_booked from public.departures where id = '22222222-0000-4000-8000-000000000005') <> 0 then
    raise exception 'FAIL: seats not released';
  end if;
end $$;

-- 14. Booking references are generated
do $$ begin
  if (select reference from public.bookings where id = 'bbbbbbbb-0000-4000-8000-000000000001') !~ '^OT[0-9]{6}$' then
    raise exception 'FAIL: booking reference format';
  end if;
end $$;

select 'ALL RLS AND CONSTRAINT TESTS PASSED' as result;
