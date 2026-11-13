-- =====================================================================
-- Seed data for development and demos.
-- Based on Owen Tours' real trips (from their Instagram). Prices, dates,
-- departure areas and meeting places marked "placeholder" must be
-- confirmed with the client before launch.
-- Test users are NOT created here: see README "Test accounts".
-- =====================================================================

-- ---------------- Company ----------------
insert into public.company_settings
  (id, company_name, registered_name, tagline, phone, whatsapp, email, address,
   facebook_url, instagram_url, tiktok_url, about_text)
values
  (1, 'Owen Tours and Travel', 'Owen Tours (Pty) Ltd', 'Explore the World',
   '+27762422251', '+27762422251', 'owentours@outlook.com',
   'Office address to be confirmed (placeholder)',
   null, 'https://www.instagram.com/owen_tours', null,
   'Want to go on a tour but you don''t know where to begin? Worry not, Owen Tours & Travels is here for you. '
   || 'We plan local trips, cross-border getaways and youth adventure camps, and help with flights, '
   || 'accommodation, visas and travel insurance.')
on conflict (id) do update set
  company_name = excluded.company_name, registered_name = excluded.registered_name,
  tagline = excluded.tagline, phone = excluded.phone, whatsapp = excluded.whatsapp,
  email = excluded.email, instagram_url = excluded.instagram_url, about_text = excluded.about_text;

-- ---------------- Trips ----------------
insert into public.trips
  (id, title, destination, destination_country, category, audience, min_grade, max_grade,
   activities, tagline, description,
   transport_included, transport_type, transport_notes,
   meals_breakfast, meals_lunch, meals_dinner, meals_snacks, meals_notes,
   accommodation_included, accommodation_type, accommodation_notes,
   includes, excludes, is_published)
values
  ('11111111-0000-4000-8000-000000000001',
   'Lesotho – Afriski Snow Trip', 'Afriski, Lesotho', 'Lesotho', 'snow', 'everyone', null, null,
   array['Snow play', 'Skiing (optional lessons)', 'Mountain views at 3 222 m'],
   'Adventure. Culture. Unforgettable Memories.',
   'Three days in the snow at Afriski, one of the highest ski resorts in Africa. Travel together from Mpumalanga, '
   || 'stay in the mountains and experience a real African winter.',
   true, 'bus', 'Return transport from the departure area',
   true, false, false, false, 'Daily breakfast',
   true, 'lodge', 'Accommodation for the whole stay',
   array['Entrance fee to Afriski'], array['Ski equipment hire and lessons', 'Lunch and dinner', 'Spending money'],
   true),

  ('11111111-0000-4000-8000-000000000002',
   'Mozambique Beach Getaway', 'Mozambique', 'Mozambique', 'beach', 'everyone', null, null,
   array['Beach days', 'Swimming', 'Local markets'],
   'Sun, sea and good company this December.',
   'Four days on the Mozambican coast with 3 nights accommodation and breakfast for the entire stay. '
   || 'Price is a placeholder until confirmed by Owen Tours.',
   true, 'bus', 'Return transport from the departure area',
   true, false, false, false, 'Breakfast for the entire stay',
   true, 'guesthouse', '3 nights accommodation',
   array[]::text[], array['Lunch and dinner', 'Activities', 'Spending money'],
   true),

  ('11111111-0000-4000-8000-000000000003',
   'Youth Adventure Camp – Queens River', 'Queens River, Mpumalanga', 'South Africa', 'youth_camp', 'high_school', 8, 12,
   array['Hiking', 'Obstacle course', 'Swimming', 'Draw your surroundings', 'Water balloons', 'Movie night'],
   'Teamwork, confidence and nature for high school learners.',
   'A 3-day, 2-night camp for Grade 8 to 12 learners. The camp develops teamwork and leadership skills, builds '
   || 'confidence and self-esteem, fosters responsibility and self-awareness, and teaches nature conservation. '
   || 'Learners are supervised and coordinated by adult professionals at all times.',
   true, 'bus', 'Return transport included',
   true, true, true, true, 'All meals included',
   true, 'camping', '2 nights camp accommodation',
   array['All activities', 'Adult supervision'], array['Spending money'],
   true),

  ('11111111-0000-4000-8000-000000000004',
   'Explore Graskop', 'Graskop, Mpumalanga', 'South Africa', 'day_trip', 'everyone', null, null,
   array['Viewpoints', 'Waterfalls', 'Graskop Gorge'],
   'Explore Graskop from just R900 per person.',
   'A day exploring Graskop and the Panorama Route: viewpoints, waterfalls and the famous pancakes.',
   true, 'minibus', null,
   false, false, false, false, null,
   false, null, null,
   array['Tour guide'], array['Meals', 'Optional activities (e.g. Graskop Gorge Lift)'],
   true),

  ('11111111-0000-4000-8000-000000000005',
   'Cape Town Experience', 'Cape Town, Western Cape', 'South Africa', 'city', 'everyone', null, null,
   array['Clifton beaches', 'Table Mountain', 'V&A Waterfront', 'Bo-Kaap'],
   'Beaches, mountains and the Mother City.',
   'A long weekend in Cape Town: Clifton beaches, Table Mountain views and the city''s best spots. '
   || 'Price is a placeholder until confirmed by Owen Tours.',
   true, 'flight', 'Return flights (placeholder – confirm with Owen Tours)',
   true, false, false, false, 'Daily breakfast',
   true, 'hotel', null,
   array['Airport transfers'], array['Lunch and dinner', 'Table Mountain cableway ticket', 'Spending money'],
   true),

  ('11111111-0000-4000-8000-000000000006',
   'Hiking with O.T', 'Mpumalanga waterfalls and forests', 'South Africa', 'hiking', 'adults_only', null, null,
   array['Guided hike', 'Waterfalls', 'Forest trails'],
   'Fresh air, waterfalls and great company.',
   'A guided day hike through Mpumalanga''s waterfalls and forests. Price is a placeholder until confirmed.',
   true, 'minibus', null,
   false, false, false, true, 'Snacks and water on the trail',
   false, null, null,
   array['Hiking guide'], array['Meals'],
   true)
on conflict (id) do nothing;

update public.trips set cover_image_url = 'https://placehold.co/1200x800/063B4C/F7E7CE?text=' || replace(title, ' ', '+')
where cover_image_url is null;

-- ---------------- Itineraries ----------------
insert into public.itinerary_days (trip_id, day_number, title, description) values
  ('11111111-0000-4000-8000-000000000001', 1, 'Travel to Lesotho', 'Depart early from Mpumalanga, cross the border and check in at Afriski.'),
  ('11111111-0000-4000-8000-000000000001', 2, 'Snow day', 'A full day in the snow. Ski lessons and equipment hire are optional extras.'),
  ('11111111-0000-4000-8000-000000000001', 3, 'Return home', 'Breakfast, last photos in the snow and the drive home.'),
  ('11111111-0000-4000-8000-000000000002', 1, 'Travel to Mozambique', 'Depart from Mpumalanga, cross the border and check in.'),
  ('11111111-0000-4000-8000-000000000002', 2, 'Beach day', 'Relax on the beach and swim.'),
  ('11111111-0000-4000-8000-000000000002', 3, 'Explore', 'Local markets and free time.'),
  ('11111111-0000-4000-8000-000000000002', 4, 'Return home', 'Breakfast and the drive home.'),
  ('11111111-0000-4000-8000-000000000003', 1, 'Arrival and team building', 'Arrive at Queens River, set up camp, obstacle course and team games.'),
  ('11111111-0000-4000-8000-000000000003', 2, 'Hiking and nature', 'Guided hike, nature conservation session, swimming, drawing and movie night.'),
  ('11111111-0000-4000-8000-000000000003', 3, 'Reflection and home', 'Leadership reflection session, water balloons and return home.'),
  ('11111111-0000-4000-8000-000000000004', 1, 'Graskop day trip', 'Panorama Route viewpoints, waterfalls and Graskop town.'),
  ('11111111-0000-4000-8000-000000000005', 1, 'Arrive in Cape Town', 'Fly in, check in and sunset at Clifton.'),
  ('11111111-0000-4000-8000-000000000005', 2, 'Mountain and city', 'Table Mountain, Bo-Kaap and the V&A Waterfront.'),
  ('11111111-0000-4000-8000-000000000005', 3, 'Beaches and home', 'Morning at the beach and the flight home.'),
  ('11111111-0000-4000-8000-000000000006', 1, 'Guided hike', 'A guided hike past waterfalls and through forest trails.')
on conflict (trip_id, day_number) do nothing;

-- ---------------- Departures ----------------
-- Times are in South African time (+02:00). Departure areas and meeting places are placeholders.
insert into public.departures
  (id, trip_id, departure_province, departure_area, meeting_place, departure_at, return_date,
   capacity, adult_price_cents, child_price_cents, booking_deadline,
   allow_instalments, deposit_cents, final_payment_due,
   is_cancellable, cancellation_deadline, refund_type, refund_percent, deposit_refundable, cancellation_notes)
values
  -- Lesotho: R4 600, R1 000 non-refundable deposit, instalments allowed
  ('22222222-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000001',
   'Mpumalanga', 'Mbombela', 'Meeting place to be confirmed (placeholder)',
   '2027-07-09 04:00+02', '2027-07-11', 30, 460000, 460000, '2027-06-25 23:59+02',
   true, 100000, '2027-06-30',
   true, '2027-06-25 23:59+02', 'full', null, false,
   'The R1 000 deposit is non-refundable. The rest is refunded if you cancel before the deadline.'),
  ('22222222-0000-4000-8000-000000000002', '11111111-0000-4000-8000-000000000001',
   'Mpumalanga', 'eMalahleni', 'Meeting place to be confirmed (placeholder)',
   '2027-07-16 04:00+02', '2027-07-18', 30, 460000, 460000, '2027-07-02 23:59+02',
   true, 100000, '2027-07-07',
   true, '2027-07-02 23:59+02', 'full', null, false,
   'The R1 000 deposit is non-refundable. The rest is refunded if you cancel before the deadline.'),

  -- Mozambique: placeholder price, non-refundable deposit, 50% refund on the rest
  ('22222222-0000-4000-8000-000000000003', '11111111-0000-4000-8000-000000000002',
   'Mpumalanga', 'Mbombela', 'Meeting place to be confirmed (placeholder)',
   '2026-12-17 05:00+02', '2026-12-20', 25, 550000, 400000, '2026-12-03 23:59+02',
   true, 150000, '2026-12-05',
   true, '2026-12-03 23:59+02', 'partial', 50, false,
   'Deposit is non-refundable. 50% of the rest is refunded if you cancel before 3 December. Price is a placeholder.'),

  -- Youth camp: R750 per learner, non-refundable
  ('22222222-0000-4000-8000-000000000004', '11111111-0000-4000-8000-000000000003',
   'Mpumalanga', 'Mbombela', 'Meeting place to be confirmed (placeholder)',
   '2026-12-04 07:00+02', '2026-12-06', 60, 75000, 75000, '2026-11-27 23:59+02',
   false, 0, null,
   false, null, 'none', null, false,
   'Non-refundable once booked.'),

  -- Graskop: R900, fully refundable (test case for a free cancellation)
  ('22222222-0000-4000-8000-000000000005', '11111111-0000-4000-8000-000000000004',
   'Mpumalanga', 'Mbombela', 'Meeting place to be confirmed (placeholder)',
   '2027-02-13 06:30+02', '2027-02-13', 14, 90000, 60000, '2027-02-10 23:59+02',
   false, 0, null,
   true, '2027-02-06 23:59+02', 'full', null, true,
   'Free cancellation with a full refund until 6 February.'),
  ('22222222-0000-4000-8000-000000000006', '11111111-0000-4000-8000-000000000004',
   'Gauteng', 'Johannesburg', 'Meeting place to be confirmed (placeholder)',
   '2027-03-13 05:00+02', '2027-03-13', 14, 110000, 80000, '2027-03-10 23:59+02',
   false, 0, null,
   true, '2027-03-06 23:59+02', 'full', null, true,
   'Free cancellation with a full refund until 6 March.'),

  -- Cape Town: placeholder price, instalments allowed
  ('22222222-0000-4000-8000-000000000007', '11111111-0000-4000-8000-000000000005',
   'Mpumalanga', 'Mbombela', 'Kruger Mpumalanga International Airport (placeholder)',
   '2027-04-23 08:00+02', '2027-04-25', 20, 850000, 650000, '2027-03-31 23:59+02',
   true, 200000, '2027-04-05',
   true, '2027-03-31 23:59+02', 'partial', 50, false,
   'Deposit is non-refundable. 50% of the rest is refunded before 31 March. Price is a placeholder.'),

  -- Hiking: placeholder price, adults only
  ('22222222-0000-4000-8000-000000000008', '11111111-0000-4000-8000-000000000006',
   'Mpumalanga', 'Sabie', 'Meeting place to be confirmed (placeholder)',
   '2027-03-20 06:00+02', '2027-03-20', 16, 65000, 65000, '2027-03-17 23:59+02',
   false, 0, null,
   true, '2027-03-13 23:59+02', 'full', null, true,
   'Free cancellation with a full refund until 13 March. Price is a placeholder.')
on conflict (id) do nothing;

-- ---------------- Specials ----------------
-- Based on the real Youth Month offer. Dates set to June 2027.
insert into public.specials
  (id, name, description, type, percent_off, min_travellers, promo_code, is_public, max_uses, starts_at, ends_at, is_active)
values
  ('33333333-0000-4000-8000-000000000001', 'Youth Month Special',
   '10% off selected local and cross-border trips during Youth Month.',
   'percentage', 10, null, null, true, null, '2027-06-01 00:00+02', '2027-06-30 23:59+02', true),
  ('33333333-0000-4000-8000-000000000002', 'Youth Month Student Discount',
   '10% off with a valid student ID.',
   'student', 10, null, null, true, null, '2027-06-01 00:00+02', '2027-06-30 23:59+02', true),
  ('33333333-0000-4000-8000-000000000003', 'Group Tours Special',
   '15% off group bookings of 5 or more.',
   'group', 15, 5, null, true, null, '2027-06-01 00:00+02', '2027-06-30 23:59+02', true),
  ('33333333-0000-4000-8000-000000000004', 'TEST10 – delete before launch',
   'Test promo code for development only.',
   'promo_code', 10, null, 'TEST10', false, 100, '2026-11-01 00:00+02', '2027-12-31 23:59+02', true)
on conflict (id) do nothing;

insert into public.special_trips (special_id, trip_id)
select s.id, t.id
from public.specials s
cross join public.trips t
where s.id in ('33333333-0000-4000-8000-000000000001', '33333333-0000-4000-8000-000000000002',
               '33333333-0000-4000-8000-000000000003', '33333333-0000-4000-8000-000000000004')
  and t.audience <> 'high_school'
on conflict do nothing;

-- ---------------- Past trips ----------------
insert into public.past_trips
  (id, trip_id, title, destination, travelled_on, traveller_count, story, cover_url, is_featured, is_published, sort_order)
values
  ('44444444-0000-4000-8000-000000000001', '11111111-0000-4000-8000-000000000005',
   'Cape Town – April 2025', 'Cape Town', '2025-04-27', null,
   'Clifton beaches, blue skies and the mountain behind us. Replace with the real story and photos.',
   'https://placehold.co/1200x800/007C91/FFFFFF?text=Cape+Town+2025', true, true, 1),
  ('44444444-0000-4000-8000-000000000002', '11111111-0000-4000-8000-000000000006',
   'Hiking with O.T', 'Mpumalanga waterfalls', '2025-09-20', null,
   'Waterfalls, forest trails and great company. Replace with the real story and photos.',
   'https://placehold.co/1200x800/4F8A6D/FFFFFF?text=Hiking+with+O.T', true, true, 2),
  ('44444444-0000-4000-8000-000000000003', '11111111-0000-4000-8000-000000000003',
   'Youth Adventure Camp – December 2025', 'Queens River', '2025-12-05', null,
   'Three days of teamwork, hiking and fun at Queens River. Replace with the real story and photos.',
   'https://placehold.co/1200x800/063B4C/F7E7CE?text=Adventure+Camp+2025', false, true, 3),
  ('44444444-0000-4000-8000-000000000004', '11111111-0000-4000-8000-000000000001',
   'Lesotho – Afriski', 'Afriski, Lesotho', '2026-07-10', null,
   'Snow, mountains and memories. Replace with the real story and photos.',
   'https://placehold.co/1200x800/063B4C/FFFFFF?text=Lesotho+Afriski', false, true, 4)
on conflict (id) do nothing;

insert into public.past_trip_media (past_trip_id, media_type, url, thumbnail_url, caption, sort_order)
select p.id, 'image',
       'https://placehold.co/1600x1200/F7E7CE/063B4C?text=Photo+' || n,
       'https://placehold.co/400x300/F7E7CE/063B4C?text=Photo+' || n,
       'Placeholder photo ' || n, n
from public.past_trips p
cross join generate_series(1, 4) as n
where not exists (select 1 from public.past_trip_media m where m.past_trip_id = p.id);

-- Sample testimonials are UNPUBLISHED on purpose: they are not real customer
-- words. Replace them with real feedback (with permission) before publishing.
insert into public.testimonials (past_trip_id, customer_name, quote, rating, is_published)
select p.id, 'Sample customer (replace)', 'Sample testimonial – replace with real customer feedback.', 5, false
from public.past_trips p
where not exists (select 1 from public.testimonials t where t.past_trip_id = p.id);
