-- =========================================================
-- 015 — Somewhere for a profile photo to live
-- =========================================================
--
-- `users.profile_photo_url` has existed since `001_initial_schema.sql`. **No storage bucket
-- has ever existed**, so nothing on the platform could produce a value for it — Academy's
-- Profile screen renders the avatar from initials and carries a note saying an upload is
-- impossible, which was accurate rather than a shortcut.
--
-- This creates the bucket and the policies. Uploading, and compressing on the way through,
-- is the app's job.
--
-- ---------------------------------------------------------
-- Why a public bucket, and what that does and doesn't mean
-- ---------------------------------------------------------
--
-- `public = true` means the *object URL* needs no signature to fetch. It does **not** mean
-- anybody can write: the policies below still decide that, and they're the same
-- own-row rules as everywhere else.
--
-- The alternative is a private bucket with signed URLs, which expire. That buys very
-- little here — a profile photo is shown to everyone in the directory anyway, so the URL
-- is not a secret — and costs a signing round trip on every avatar in a list of forty
-- people, on connections where that is the difference between a screen loading and not.
-- The thing that would change this decision is photos becoming sensitive; they aren't.
--
-- **A path is not a secret either.** Object names are `<user id>/<random>.<ext>`, so a URL
-- reveals a user id — which is already visible to any signed-in reader of the directory.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'profile-photos',
  'profile-photos',
  true,
  -- 2 MB, enforced by storage itself rather than only by the upload form. The app
  -- compresses before it gets here and should land far under this; the limit is what stops
  -- a direct API call from filling the bucket.
  2097152,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update
  set public = excluded.public,
      file_size_limit = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;

-- ---------------------------------------------------------
-- Who may write what
-- ---------------------------------------------------------
--
-- The first path segment is the owner's user id, and every policy below pins it to
-- `auth.uid()`. That is the whole authorization model: you write inside your own folder and
-- nowhere else. `storage.foldername(name)` splits the object name on '/', and PostgreSQL
-- arrays are 1-indexed, so `[1]` is the first segment.

drop policy if exists profile_photos_read on storage.objects;
drop policy if exists profile_photos_insert on storage.objects;
drop policy if exists profile_photos_update on storage.objects;
drop policy if exists profile_photos_delete on storage.objects;

-- Readable by anyone, matching the public bucket. Stated as a policy anyway so the rule is
-- visible here rather than implied by a boolean three statements up.
create policy profile_photos_read on storage.objects for select
  using (bucket_id = 'profile-photos');

create policy profile_photos_insert on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Replacing a photo. The app writes a new randomised name and deletes the old one rather
-- than overwriting in place — a CDN happily serves a cached copy of a replaced object, and
-- "I changed my photo and it didn't change" is the bug that follows.
create policy profile_photos_update on storage.objects for update
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  )
  with check (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy profile_photos_delete on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'profile-photos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- ---------------------------------------------------------
-- The column the URL lands in
-- ---------------------------------------------------------
--
-- `users_update_own` already exists (`id = auth.uid() or auth_is_admin()`) and covers this.
-- But a policy that lets somebody write their own `profile_photo_url` also lets them write
-- **every other column of their own row**, because whether that's possible is decided by
-- the column grant rather than the policy — and there wasn't one.
--
-- The column that matters is `email`. `public.users.email` and `auth.users.email` are
-- separate stores of the same fact, and only the second one is a sign-in credential.
-- Changing one without the other silently desynchronises an account from its login —
-- which is precisely why Academy's Profile screen renders email and phone as read-only
-- rows rather than fields. That was a UI decision protecting a database that permitted it
-- anyway; this makes the database agree.
--
-- `deleted_at` is included because Admin-web's archive control writes it
-- (`setUserArchived`), and leaving it out would break archiving the moment this migration
-- ran. Self-archiving stays possible for the same reason it already was — the policy has
-- always allowed a person to write their own row, and narrowing *that* is a separate
-- decision from narrowing which columns exist to write.

revoke update on users from anon, authenticated;
grant update (
  name,
  phone,
  location,
  profile_photo_url,
  preferred_language,
  deleted_at
) on users to authenticated;

comment on column users.profile_photo_url is
  'Public URL of an object in the `profile-photos` bucket. Written by the app after compressing and uploading; null means fall back to initials, which is still the normal case.';
