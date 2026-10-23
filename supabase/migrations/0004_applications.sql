-- Bauhaven Admin - applications
--
-- Shape follows 04_BAUHAVEN_DATABASE_SCHEMA.md section 6.3 and the example
-- DDL in section 17, with a few additive columns (duplicate_flag/reason,
-- answers broken into typed jsonb sub-fields, documents/links) that the
-- Stitch "Application detail" screens actually render and which the schema
-- doc does not forbid - `answers jsonb` there is deliberately generic.
--
-- IMPORTANT: bauhaven-website already writes to a table called `applications`
-- with yet another, inconsistent shape (see the completion report). This
-- migration only adds columns that are missing - it never drops or renames
-- a column bauhaven-website might already depend on. Confirm against the
-- live schema (`supabase db pull`) before applying, and reconcile
-- bauhaven-website's column drift separately.

create table if not exists public.applications (
  id uuid primary key default gen_random_uuid()
);

-- submitted_at must exist before the created_at backfill below can read it.
alter table public.applications add column if not exists submitted_at timestamptz;

-- The live table (83 real rows from bauhaven-website's public form) has
-- `submitted_at` but no `created_at` at all - added as nullable first,
-- backfilled from submitted_at, then locked down, rather than relying on
-- the CREATE TABLE above (which is a no-op once the table already exists).
alter table public.applications add column if not exists created_at timestamptz;
update public.applications set created_at = submitted_at
  where created_at is null and submitted_at is not null;
update public.applications set created_at = now() where created_at is null;
alter table public.applications alter column created_at set default now();
alter table public.applications alter column created_at set not null;

alter table public.applications add column if not exists tracking_code text;
alter table public.applications add column if not exists offering_id uuid references public.offerings (id);
alter table public.applications add column if not exists applicant_profile_id uuid references public.profiles (id);
alter table public.applications add column if not exists applicant_email citext not null default '';
alter table public.applications add column if not exists applicant_phone text;
alter table public.applications add column if not exists applicant_name text not null default '';
alter table public.applications add column if not exists applicant_location text;
alter table public.applications add column if not exists answers jsonb not null default '[]'::jsonb;
alter table public.applications add column if not exists education jsonb not null default '[]'::jsonb;
alter table public.applications add column if not exists experience jsonb not null default '[]'::jsonb;
alter table public.applications add column if not exists links jsonb not null default '{}'::jsonb;
alter table public.applications add column if not exists documents jsonb not null default '[]'::jsonb;
alter table public.applications add column if not exists status public.application_status not null default 'submitted';
alter table public.applications add column if not exists assigned_reviewer_id uuid references public.profiles (id);
alter table public.applications add column if not exists decision_reason text;
alter table public.applications add column if not exists duplicate_flag boolean not null default false;
alter table public.applications add column if not exists duplicate_reason text;
alter table public.applications add column if not exists consent_snapshot jsonb not null default '{}'::jsonb;
alter table public.applications add column if not exists updated_at timestamptz not null default now();

-- Legacy compatibility: bauhaven-website's own code (Apply.js) may already
-- be inserting into a `full_name`/`email`/`phone` shape on the live table.
-- This migration deliberately does NOT rename or alias those columns - it
-- cannot tell, without live access, whether they hold real historical data
-- or don't exist at all. Instead, do a one-directional, one-time backfill:
-- copy legacy -> canonical only where the legacy column exists and the
-- canonical value is still blank. Never the reverse, and never a generated
-- column, since either could silently misattribute or mask real data.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='applications' and column_name='full_name') then
    update public.applications set applicant_name = full_name
      where (applicant_name is null or applicant_name = '') and full_name is not null;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='applications' and column_name='email') then
    update public.applications set applicant_email = email
      where (applicant_email is null or applicant_email = '') and email is not null;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='applications' and column_name='phone') then
    update public.applications set applicant_phone = phone
      where applicant_phone is null and phone is not null;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='applications' and column_name='applicant_id') then
    update public.applications set applicant_profile_id = applicant_id
      where applicant_profile_id is null and applicant_id is not null;
  end if;
end $$;

-- Prefer the live `reference` column (already unique-ish, human-readable)
-- over generating a new code, so existing applicants keep the reference
-- they may already have been shown.
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='applications' and column_name='reference') then
    update public.applications set tracking_code = reference
      where tracking_code is null and reference is not null;
  end if;
end $$;

update public.applications
set tracking_code = 'REF-' || to_char(created_at, 'YYYY') || '-' || substr(id::text, 1, 6)
where tracking_code is null;

alter table public.applications alter column tracking_code set not null;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'applications_tracking_code_key') then
    alter table public.applications add constraint applications_tracking_code_key unique (tracking_code);
  end if;
end $$;

create index if not exists applications_status_submitted_idx
  on public.applications (status, submitted_at desc);
create index if not exists applications_offering_status_idx
  on public.applications (offering_id, status);
create index if not exists applications_email_idx on public.applications (lower(applicant_email::text));
create index if not exists applications_created_at_idx on public.applications (created_at desc);

drop trigger if exists applications_set_updated_at on public.applications;
create trigger applications_set_updated_at
  before update on public.applications
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- application_status_history: append-only (04_BAUHAVEN_DATABASE_SCHEMA.md
-- section 6.4). Populated automatically by a trigger, never written to
-- directly by any client - see 0007_rls_policies.sql.
-- ---------------------------------------------------------------------------
create table if not exists public.application_status_history (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  from_status public.application_status,
  to_status public.application_status not null,
  actor_id uuid references public.profiles (id),
  reason text,
  created_at timestamptz not null default now()
);

create index if not exists application_status_history_application_id_idx
  on public.application_status_history (application_id, created_at desc);

create or replace function public.record_application_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.application_status_history (application_id, from_status, to_status, actor_id, reason)
    values (new.id, null, new.status, auth.uid(), new.decision_reason);
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
    insert into public.application_status_history (application_id, from_status, to_status, actor_id, reason)
    values (new.id, old.status, new.status, auth.uid(), new.decision_reason);
  end if;
  return new;
end;
$$;

drop trigger if exists applications_record_status_history on public.applications;
create trigger applications_record_status_history
  after insert or update on public.applications
  for each row execute function public.record_application_status_change();

-- ---------------------------------------------------------------------------
-- application_reviews: internal reviewer notes, never shown to applicants
-- (04_BAUHAVEN_DATABASE_SCHEMA.md section 6.5). Named `application_reviews`
-- to match the canonical schema doc (this repo's first draft called it
-- `application_notes` - renamed for consistency with the shared contract).
-- ---------------------------------------------------------------------------
create table if not exists public.application_reviews (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  reviewer_id uuid references public.profiles (id),
  note text not null,
  recommendation text check (recommendation in ('approve', 'reject', 'waitlist', 'request_clarification') or recommendation is null),
  created_at timestamptz not null default now()
);

create index if not exists application_reviews_application_id_idx
  on public.application_reviews (application_id, created_at desc);

-- ---------------------------------------------------------------------------
-- application_approvals: one approved decision per application
-- (04_BAUHAVEN_DATABASE_SCHEMA.md section 6.7). Written only by the
-- approve-application Edge Function (service role) - this is the durable
-- record of "what exactly got approved" (offering/cohort at time of
-- decision), independent of whatever offerings/cohorts later become.
-- ---------------------------------------------------------------------------
create table if not exists public.application_approvals (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  decided_by uuid references public.profiles (id),
  decided_at timestamptz not null default now(),
  approved_offering_id uuid references public.offerings (id),
  approved_cohort_id uuid references public.cohorts (id),
  enrolment_id uuid,
  assigned_role text not null default 'Intern',
  mentor_id uuid references public.profiles (id),
  start_date date,
  end_date date
);

create unique index if not exists application_approvals_application_id_unique
  on public.application_approvals (application_id);
