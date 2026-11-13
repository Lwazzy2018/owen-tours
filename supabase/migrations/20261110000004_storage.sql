-- =====================================================================
-- Storage buckets
-- Uploads go through the ASP.NET API (which resizes images and creates
-- thumbnails), so clients only need read access to the public buckets.
-- =====================================================================

insert into storage.buckets (id, name, public)
values
  ('trip-media', 'trip-media', true),            -- trip photos (public)
  ('past-trip-media', 'past-trip-media', true),  -- "Our Previous Trips" photos and videos (public)
  ('student-ids', 'student-ids', false),         -- student ID photos (PRIVATE, POPIA)
  ('documents', 'documents', false)              -- generated PDFs if stored (PRIVATE)
on conflict (id) do nothing;

create policy "Public read for trip media"
  on storage.objects for select to anon, authenticated
  using (bucket_id in ('trip-media', 'past-trip-media'));

-- No client policies for student-ids or documents: only the API (service role)
-- can read or write them, and it hands out short-lived signed URLs to the
-- owner and to admins.
