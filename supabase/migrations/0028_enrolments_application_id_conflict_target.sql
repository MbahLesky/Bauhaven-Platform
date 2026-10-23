-- Fix: approve-application's enrolment upsert can never succeed.
--
-- The Edge Function does:
--   admin.from('enrolments').upsert({...}, { onConflict: 'application_id' })
-- which compiles to `INSERT ... ON CONFLICT (application_id) DO UPDATE ...`
-- with no WHERE clause. Postgres will only use a *partial* unique index for
-- ON CONFLICT inference when the conflict clause's own predicate matches the
-- index's WHERE clause exactly - and the Supabase JS client never emits one.
--
-- enrolments_application_id_unique (0005_invitations_and_enrolments.sql) is
-- partial (`where application_id is not null`), so the bare conflict target
-- above was never usable. Every approval failed at the finalising step with
-- "Failed to create enrolment: there is no unique or exclusion constraint
-- matching the ON CONFLICT specification" (confirmed live, 2026-08-08).
--
-- A plain (non-partial) unique index already tolerates any number of NULL
-- application_id rows on its own - NULLs never conflict with each other in
-- a unique index, partial or not - so dropping the WHERE clause changes
-- nothing about what data is allowed. It only makes the index usable for
-- inference, which is the actual bug.
drop index if exists public.enrolments_application_id_unique;

create unique index if not exists enrolments_application_id_unique
  on public.enrolments (application_id);
