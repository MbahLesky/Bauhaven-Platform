-- Bauhaven Admin - Programmes, Cohorts and People (Phase 3)
--
-- Widens the minimal `offerings`/`cohorts` lookup tables from migration
-- 0003 (built only to give `applications.offering_id` a real FK target)
-- into the actual manageable catalogue BAU-DB-002 sections 7.1-7.4
-- describe, and adds the People-module tables (participant_profiles,
-- cohort_staff_assignments, programme_milestones). All additive.

-- ---------------------------------------------------------------------------
-- offerings: widen with operational/public fields, application window,
-- capacity (BAU-DB-002 section 7.1). offering_type/publication_status keep
-- their existing enum/check types from 0001/0003 - not touched here.
-- ---------------------------------------------------------------------------
alter table public.offerings add column if not exists code text;
alter table public.offerings add column if not exists short_description text;
alter table public.offerings add column if not exists operational_description text;
alter table public.offerings add column if not exists public_description text;
alter table public.offerings add column if not exists eligibility jsonb not null default '{}'::jsonb;
alter table public.offerings add column if not exists delivery_mode text;
alter table public.offerings add column if not exists location_text text;
alter table public.offerings add column if not exists default_duration_text text;
alter table public.offerings add column if not exists capacity integer check (capacity is null or capacity > 0);
alter table public.offerings add column if not exists application_opens_at timestamptz;
alter table public.offerings add column if not exists application_closes_at timestamptz;
alter table public.offerings add column if not exists is_accepting_applications boolean not null default false;
alter table public.offerings add column if not exists operational_status text not null default 'draft'
  check (operational_status in ('draft', 'active', 'paused', 'closed', 'archived'));
alter table public.offerings add column if not exists published_at timestamptz;
alter table public.offerings add column if not exists created_by uuid references public.profiles (id);
alter table public.offerings add column if not exists updated_by uuid references public.profiles (id);

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'offerings_code_key') then
    update public.offerings set code = slug where code is null;
    alter table public.offerings add constraint offerings_code_key unique (code);
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- cohorts: widen with capacity/delivery overrides/closure (section 7.2).
-- Kept this repo's existing `starts_at`/`ends_at` column names (already in
-- use since migration 0003) rather than renaming to the doc's
-- `start_date`/`end_date` - same meaning, renaming live columns for a
-- cosmetic match isn't worth the churn.
-- ---------------------------------------------------------------------------
alter table public.cohorts add column if not exists capacity integer check (capacity is null or capacity > 0);
alter table public.cohorts add column if not exists delivery_mode text;
alter table public.cohorts add column if not exists location_text text;
alter table public.cohorts add column if not exists closed_at timestamptz;
alter table public.cohorts add column if not exists created_by uuid references public.profiles (id);
alter table public.cohorts add column if not exists updated_by uuid references public.profiles (id);

-- ---------------------------------------------------------------------------
-- cohort_staff_assignments (section 7.3): operational assignment, distinct
-- from the platform permission grant in user_role_assignments - this
-- records *who does what* on a cohort; user_role_assignments records *what
-- they're allowed to do*. Both are checked together where relevant.
-- ---------------------------------------------------------------------------
create table if not exists public.cohort_staff_assignments (
  id uuid primary key default gen_random_uuid(),
  cohort_id uuid not null references public.cohorts (id) on delete cascade,
  staff_profile_id uuid not null references public.profiles (id),
  responsibility text not null check (responsibility in ('manager', 'coordinator', 'mentor', 'reviewer', 'instructor')),
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create index if not exists cohort_staff_assignments_cohort_id_idx on public.cohort_staff_assignments (cohort_id);
create index if not exists cohort_staff_assignments_staff_profile_id_idx on public.cohort_staff_assignments (staff_profile_id);

-- ---------------------------------------------------------------------------
-- programme_milestones (section 7.4).
-- ---------------------------------------------------------------------------
create table if not exists public.programme_milestones (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid references public.offerings (id) on delete cascade,
  cohort_id uuid references public.cohorts (id) on delete cascade,
  title text not null,
  description text,
  due_at timestamptz,
  sort_order integer not null default 0,
  is_visible_to_participants boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint programme_milestones_context_required check (offering_id is not null or cohort_id is not null)
);

drop trigger if exists programme_milestones_set_updated_at on public.programme_milestones;
create trigger programme_milestones_set_updated_at
  before update on public.programme_milestones
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- participant_profiles (BAU-DB-002 section 5.2): participant-specific
-- extension of `profiles`, mirroring `staff_profiles` from migration 0009.
-- ---------------------------------------------------------------------------
create table if not exists public.participant_profiles (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  date_of_birth date,
  gender text,
  address_text text,
  city text,
  country_code text,
  education_level text,
  institution_name text,
  emergency_contact_name text,
  emergency_contact_phone text,
  bio text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists participant_profiles_set_updated_at on public.participant_profiles;
create trigger participant_profiles_set_updated_at
  before update on public.participant_profiles
  for each row execute function public.set_updated_at();
