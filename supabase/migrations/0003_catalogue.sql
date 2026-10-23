-- Bauhaven Admin - minimal catalogue (offerings, cohorts)
--
-- The Admissions MVP needs `applications.offering_id` to be a real foreign
-- key (04_BAUHAVEN_DATABASE_SCHEMA.md section 6.3), so these two lookup
-- tables exist here. This is intentionally NOT the full Offerings/Cohorts
-- admin module described in section 5.1 of the Interface Design doc
-- (no SEO fields, no CMS publication workflow, no capacity/roster
-- management UI) - there is no approved Stitch design for that module yet.
-- Building the full module is out of scope for this pass; see the
-- completion report backlog.

create table if not exists public.offerings (
  id uuid primary key default gen_random_uuid(),
  offering_type text not null check (
    offering_type in ('course', 'bootcamp', 'internship', 'holiday_program', 'workshop', 'training', 'mentorship', 'program')
  ),
  title text not null,
  slug citext not null unique,
  publication_status public.publication_status not null default 'draft',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists offerings_set_updated_at on public.offerings;
create trigger offerings_set_updated_at
  before update on public.offerings
  for each row execute function public.set_updated_at();

create table if not exists public.cohorts (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid not null references public.offerings (id) on delete cascade,
  code text not null,
  name text not null,
  starts_at date,
  ends_at date,
  status text not null default 'planned' check (status in ('planned', 'open', 'active', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cohorts_dates_check check (starts_at is null or ends_at is null or starts_at <= ends_at),
  unique (offering_id, code)
);

drop trigger if exists cohorts_set_updated_at on public.cohorts;
create trigger cohorts_set_updated_at
  before update on public.cohorts
  for each row execute function public.set_updated_at();
