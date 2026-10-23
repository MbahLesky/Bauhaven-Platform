-- Bauhaven Admin - Phase 5 schema: Tasks, Projects, Assignments,
-- Submissions and Feedback (BAUHAVEN_PHASE_4_5_..._PROMPT.md Part D,
-- 04_BAUHAVEN_DATABASE_SCHEMA.md section 10).
--
-- Two deliberate, documented simplifications versus the canonical schema
-- doc, both because their target tables belong to Phase 7 (Resources) and
-- don't exist yet - not silently dropped, just deferred:
--   - `task_resources` (FK to `digital_resources`) becomes a `resources
--     jsonb` array directly on `tasks` ({label, url}), until Phase 7 builds
--     a real resource catalogue to link to instead.
--   - `submission_files` (FK to `storage_objects`) becomes a `files jsonb`
--     array directly on `submissions` ({filename, url, size_bytes,
--     uploaded_at}), until Phase 7's Storage integration exists.
-- `rubrics`/`rubric_criteria` are skipped entirely per the doc's own
-- "optional for MVP... keep schema ready but do not block core feedback" -
-- `feedback.rubric_response` is free-form jsonb instead of an FK.
--
-- A third, unplanned rename: the schema doc's `projects` table collides
-- with a live, pre-existing `public.projects` table that turns out to be
-- bauhaven-website's public portfolio/showcase table (integer PK, real
-- rows: "Real Estate Listing Platform" etc.) - a completely different
-- concept that happens to share the word "projects". Confirmed live before
-- writing a single row here. Named `public.learning_projects` instead,
-- never touching the website's table, matching this repo's standing rule
-- (see migration 0004's header) to never rename/collide with something
-- another app might depend on.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'task_status') then
    create type public.task_status as enum ('draft', 'scheduled', 'published', 'closed', 'archived');
  end if;
  if not exists (select 1 from pg_type where typname = 'assignment_status') then
    create type public.assignment_status as enum (
      'assigned', 'in_progress', 'submitted', 'changes_requested',
      'completed', 'overdue', 'cancelled'
    );
  end if;
  if not exists (select 1 from pg_type where typname = 'submission_status') then
    create type public.submission_status as enum (
      'draft', 'submitted', 'under_review', 'changes_requested',
      'resubmitted', 'accepted', 'completed', 'withdrawn'
    );
  end if;
  if not exists (select 1 from pg_type where typname = 'feedback_visibility') then
    create type public.feedback_visibility as enum ('private', 'released');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- projects (04_BAUHAVEN_DATABASE_SCHEMA.md section 10.1)
-- ---------------------------------------------------------------------------
create table if not exists public.learning_projects (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid references public.offerings (id),
  cohort_id uuid references public.cohorts (id),
  title text not null,
  description text not null default '',
  status text not null default 'draft' check (status in ('draft', 'active', 'completed', 'archived')),
  starts_at timestamptz,
  ends_at timestamptz,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint learning_projects_context_required check (offering_id is not null or cohort_id is not null)
);

drop trigger if exists learning_projects_set_updated_at on public.learning_projects;
create trigger learning_projects_set_updated_at
  before update on public.learning_projects
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- tasks (section 10.2 + the task_resources simplification above)
-- ---------------------------------------------------------------------------
create table if not exists public.tasks (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid references public.offerings (id),
  cohort_id uuid references public.cohorts (id),
  project_id uuid references public.learning_projects (id),
  title text not null,
  instructions text not null default '',
  status public.task_status not null default 'draft',
  starts_at timestamptz,
  due_at timestamptz,
  submission_type text not null default 'text' check (submission_type in ('text', 'file', 'link', 'mixed', 'none')),
  allowed_file_rules jsonb not null default '{}'::jsonb,
  resources jsonb not null default '[]'::jsonb,
  allow_resubmission boolean not null default false,
  max_resubmissions integer,
  rubric_response_template jsonb,
  created_by uuid references public.profiles (id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tasks_context_required check (offering_id is not null or cohort_id is not null or project_id is not null)
);

create index if not exists tasks_offering_id_idx on public.tasks (offering_id);
create index if not exists tasks_cohort_id_idx on public.tasks (cohort_id);
create index if not exists tasks_status_idx on public.tasks (status);

drop trigger if exists tasks_set_updated_at on public.tasks;
create trigger tasks_set_updated_at
  before update on public.tasks
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- task_assignments (section 10.4) - who a task applies to. Multiple rows
-- per task cover "selected participants"; a single row with a cohort-wide
-- enrolment sweep (done at assignment-creation time in the Edge Function/
-- service layer, not by a live query join) covers "whole cohort"/"whole
-- offering" - this table always resolves to individual enrolments, which
-- keeps every downstream submission/feedback query a simple join instead
-- of needing to re-resolve "who's in this cohort right now" every time.
-- ---------------------------------------------------------------------------
create table if not exists public.task_assignments (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks (id) on delete cascade,
  enrolment_id uuid not null references public.enrolments (id) on delete cascade,
  assigned_by uuid references public.profiles (id),
  assigned_at timestamptz not null default now(),
  due_at_override timestamptz,
  reviewer_id uuid references public.profiles (id),
  status public.assignment_status not null default 'assigned',
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (task_id, enrolment_id)
);

create index if not exists task_assignments_task_id_idx on public.task_assignments (task_id);
create index if not exists task_assignments_enrolment_id_idx on public.task_assignments (enrolment_id);
create index if not exists task_assignments_reviewer_id_idx on public.task_assignments (reviewer_id);

drop trigger if exists task_assignments_set_updated_at on public.task_assignments;
create trigger task_assignments_set_updated_at
  before update on public.task_assignments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- submissions (section 10.5 + the submission_files simplification above).
-- One row per version - matches the doc's explicit "immutable final
-- submissions" + "version history" requirements: a resubmission inserts a
-- new row with version_number + 1 rather than overwriting the prior one.
-- ---------------------------------------------------------------------------
create table if not exists public.submissions (
  id uuid primary key default gen_random_uuid(),
  task_assignment_id uuid not null references public.task_assignments (id) on delete cascade,
  participant_id uuid not null references public.profiles (id),
  version_number integer not null default 1,
  status public.submission_status not null default 'draft',
  text_content text,
  link_url text,
  files jsonb not null default '[]'::jsonb,
  submitted_at timestamptz,
  is_late boolean not null default false,
  idempotency_key text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (task_assignment_id, version_number)
);

create unique index if not exists submissions_idempotency_key_unique
  on public.submissions (task_assignment_id, idempotency_key)
  where idempotency_key is not null;

create index if not exists submissions_participant_id_idx on public.submissions (participant_id);
create index if not exists submissions_task_assignment_id_idx on public.submissions (task_assignment_id);

drop trigger if exists submissions_set_updated_at on public.submissions;
create trigger submissions_set_updated_at
  before update on public.submissions
  for each row execute function public.set_updated_at();

-- Server-derived lateness and finalisation: computed here, not trusted from
-- the client, per the doc's "server timestamps"/"server confirms receipt"
-- requirements.
create or replace function public.finalise_submission()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_due_at timestamptz;
begin
  if new.status = 'submitted' and (old.status is distinct from new.status) then
    new.submitted_at := coalesce(new.submitted_at, now());
    select coalesce(ta.due_at_override, t.due_at) into v_due_at
      from public.task_assignments ta
      join public.tasks t on t.id = ta.task_id
      where ta.id = new.task_assignment_id;
    new.is_late := v_due_at is not null and new.submitted_at > v_due_at;
  end if;
  return new;
end;
$$;

drop trigger if exists submissions_finalise on public.submissions;
create trigger submissions_finalise
  before insert or update on public.submissions
  for each row execute function public.finalise_submission();

-- Keeps task_assignments.status in step with its latest submission, so the
-- review queue (Admin-side) can filter on the assignment directly instead
-- of re-deriving "latest submission status" per row on every query.
create or replace function public.sync_task_assignment_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'submitted' then
    update public.task_assignments
      set status = 'submitted'
      where id = new.task_assignment_id
        and status in ('assigned', 'in_progress', 'changes_requested');
  end if;
  return new;
end;
$$;

drop trigger if exists submissions_sync_assignment_status on public.submissions;
create trigger submissions_sync_assignment_status
  after insert or update on public.submissions
  for each row execute function public.sync_task_assignment_status();

-- ---------------------------------------------------------------------------
-- feedback (section 10.7)
-- ---------------------------------------------------------------------------
create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions (id) on delete cascade,
  reviewer_id uuid not null references public.profiles (id),
  visible_feedback text,
  private_note text,
  result text check (result in ('accepted', 'changes_requested', 'completed', 'approved') or result is null),
  score numeric,
  rubric_response jsonb,
  visibility public.feedback_visibility not null default 'private',
  allow_resubmission boolean not null default false,
  resubmission_due_at timestamptz,
  released_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists feedback_submission_id_idx on public.feedback (submission_id);

drop trigger if exists feedback_set_updated_at on public.feedback;
create trigger feedback_set_updated_at
  before update on public.feedback
  for each row execute function public.set_updated_at();

-- Releasing feedback flips the parent assignment to changes_requested/
-- completed so the participant-facing Hub (once built) can filter on the
-- assignment without joining feedback every time.
create or replace function public.apply_feedback_result()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_task_assignment_id uuid;
begin
  if new.visibility = 'released' and (old.visibility is distinct from new.visibility or old.released_at is null) then
    new.released_at := coalesce(new.released_at, now());
    select task_assignment_id into v_task_assignment_id
      from public.submissions where id = new.submission_id;
    if new.result = 'changes_requested' then
      update public.task_assignments set status = 'changes_requested' where id = v_task_assignment_id;
    elsif new.result in ('accepted', 'completed', 'approved') then
      update public.task_assignments set status = 'completed', completed_at = now() where id = v_task_assignment_id;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists feedback_apply_result on public.feedback;
create trigger feedback_apply_result
  before insert or update on public.feedback
  for each row execute function public.apply_feedback_result();
