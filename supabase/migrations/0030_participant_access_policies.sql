-- Renumbered 2026-09-11: this was `0009_participant_access_policies.sql` on MbahLesky/Bauhaven-admin `main`
-- (see 0029 for why). Already applied to keyaahfksbfigcdbbuda - do not re-run it there.
--
-- Bauhaven - Participant read access (BR-008, BR-009, FR-HUB-*)
--
-- Until now every participant-facing table was readable only by staff, so Hub
-- could not read a participant's own task, programme or released feedback.
-- This migration grants participants access to their own records and nothing
-- else.
--
-- Two rules shape everything below:
--   BR-008  a participant sees only their own data;
--   BR-009  a participant sees feedback only once it is released, and never
--           the reviewer's private note.
--
-- Scoping always runs through enrolments.profile_id = auth.uid(). That column
-- is the single definition of "mine" for a participant.

-- Helpers -------------------------------------------------------------------
-- SECURITY DEFINER so a policy on tasks can consult enrolments without
-- re-entering enrolments' own policy and recursing. STABLE so Postgres may
-- cache the result within a statement. search_path is pinned: a definer
-- function that resolves names through the caller's search_path is a
-- privilege-escalation route.

create or replace function private.is_enrolled_in_offering(target_offering_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.enrolments e
    where e.profile_id = auth.uid()
      and e.offering_id = target_offering_id
  );
$$;

create or replace function private.is_enrolled_in_cohort(target_cohort_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.enrolments e
    where e.profile_id = auth.uid()
      and e.cohort_id = target_cohort_id
  );
$$;

create or replace function private.owns_enrolment(target_enrolment_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.enrolments e
    where e.id = target_enrolment_id
      and e.profile_id = auth.uid()
  );
$$;

revoke execute on function private.is_enrolled_in_offering(uuid) from public;
revoke execute on function private.is_enrolled_in_cohort(uuid) from public;
revoke execute on function private.owns_enrolment(uuid) from public;
grant execute on function private.is_enrolled_in_offering(uuid) to authenticated;
grant execute on function private.is_enrolled_in_cohort(uuid) to authenticated;
grant execute on function private.owns_enrolment(uuid) to authenticated;

-- RLS on the tables added in 0008 -------------------------------------------

alter table public.storage_objects    enable row level security;
alter table public.attendance_sessions enable row level security;
alter table public.attendance_records enable row level security;
alter table public.announcements      enable row level security;
alter table public.notifications      enable row level security;
alter table public.digital_resources  enable row level security;
alter table public.task_resources     enable row level security;
alter table public.submission_files   enable row level security;
alter table public.policy_documents   enable row level security;
alter table public.policy_acceptances enable row level security;

-- Programme context ---------------------------------------------------------
-- A participant must be able to read the offering and cohort they are enrolled
-- in. Existing policies are admin-only, so these are additive: PERMISSIVE
-- policies OR together, and the admin policies stay untouched.

drop policy if exists offerings_select_participant on public.offerings;
create policy offerings_select_participant on public.offerings
  for select
  using (private.is_enrolled_in_offering(id));

drop policy if exists cohorts_select_participant on public.cohorts;
create policy cohorts_select_participant on public.cohorts
  for select
  using (private.is_enrolled_in_cohort(id));

drop policy if exists programme_milestones_select_participant on public.programme_milestones;
create policy programme_milestones_select_participant on public.programme_milestones
  for select
  using (
    is_visible_to_participants
    and (
      (offering_id is not null and private.is_enrolled_in_offering(offering_id))
      or (cohort_id is not null and private.is_enrolled_in_cohort(cohort_id))
    )
  );

drop policy if exists learning_projects_select_participant on public.learning_projects;
create policy learning_projects_select_participant on public.learning_projects
  for select
  using (
    (offering_id is not null and private.is_enrolled_in_offering(offering_id))
    or (cohort_id is not null and private.is_enrolled_in_cohort(cohort_id))
  );

-- Tasks ---------------------------------------------------------------------
-- FR-HUB-TASK-003: an unpublished task must never reach a participant. The
-- status guard is the whole point of this policy, so it is checked first and
-- applies to every branch below it.

drop policy if exists tasks_select_participant on public.tasks;
create policy tasks_select_participant on public.tasks
  for select
  using (
    status = 'published'
    and (
      -- Assigned directly to one of this participant's enrolments.
      exists (
        select 1
        from public.task_assignments ta
        join public.enrolments e on e.id = ta.enrolment_id
        where ta.task_id = tasks.id
          and e.profile_id = auth.uid()
      )
      -- Or published to a programme context this participant belongs to.
      or (offering_id is not null and private.is_enrolled_in_offering(offering_id))
      or (cohort_id is not null and private.is_enrolled_in_cohort(cohort_id))
    )
  );

drop policy if exists task_resources_select_participant on public.task_resources;
create policy task_resources_select_participant on public.task_resources
  for select
  using (
    exists (
      select 1 from public.tasks t
      where t.id = task_resources.task_id and t.status = 'published'
    )
  );

-- Attendance ----------------------------------------------------------------
-- Read-only for participants. Recording and correcting attendance is Admin's
-- job (FR-HUB-BOUND-001) and has no participant write policy at all.

drop policy if exists attendance_records_select_own on public.attendance_records;
create policy attendance_records_select_own on public.attendance_records
  for select
  using (private.owns_enrolment(enrolment_id));

drop policy if exists attendance_sessions_select_participant on public.attendance_sessions;
create policy attendance_sessions_select_participant on public.attendance_sessions
  for select
  using (private.is_enrolled_in_cohort(cohort_id));

-- Notifications -------------------------------------------------------------

drop policy if exists notifications_select_own on public.notifications;
create policy notifications_select_own on public.notifications
  for select
  using (recipient_id = auth.uid());

drop policy if exists notifications_update_own on public.notifications;
create policy notifications_update_own on public.notifications
  for update
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

-- RLS decides which ROWS a participant may update, not which COLUMNS. Without
-- this grant the policy above would also let them rewrite a notification's
-- title or body. Marking as read is the only participant-owned mutation.
-- Admin and Edge Functions write through the service role, which ignores both
-- the policy and this grant.
revoke update on public.notifications from authenticated;
grant update (read_at, status) on public.notifications to authenticated;

-- Announcements -------------------------------------------------------------

drop policy if exists announcements_select_participant on public.announcements;
create policy announcements_select_participant on public.announcements
  for select
  using (
    publication_status = 'published'
    and (publish_at is null or publish_at <= now())
    and (expires_at is null or expires_at > now())
    and (
      audience_type = 'organisation'
      or (audience_type = 'offering' and private.is_enrolled_in_offering(audience_id))
      or (audience_type = 'cohort' and private.is_enrolled_in_cohort(audience_id))
      or (audience_type = 'selected_users' and audience_id = auth.uid())
    )
  );

-- Resources -----------------------------------------------------------------

drop policy if exists digital_resources_select_participant on public.digital_resources;
create policy digital_resources_select_participant on public.digital_resources
  for select
  using (
    visibility_scope_type = 'organisation'
    or (visibility_scope_type = 'offering'
        and private.is_enrolled_in_offering(visibility_scope_id))
    or (visibility_scope_type = 'cohort'
        and private.is_enrolled_in_cohort(visibility_scope_id))
    -- Attached to a task this participant can already see.
    or exists (
      select 1
      from public.task_resources tr
      join public.tasks t on t.id = tr.task_id
      where tr.resource_id = digital_resources.id
        and t.status = 'published'
    )
  );

-- Submission files ----------------------------------------------------------

drop policy if exists submission_files_select_own on public.submission_files;
create policy submission_files_select_own on public.submission_files
  for select
  using (
    exists (
      select 1 from public.submissions s
      where s.id = submission_files.submission_id
        and s.participant_id = auth.uid()
    )
  );

drop policy if exists submission_files_insert_own on public.submission_files;
create policy submission_files_insert_own on public.submission_files
  for insert
  with check (
    exists (
      select 1 from public.submissions s
      where s.id = submission_files.submission_id
        and s.participant_id = auth.uid()
        and s.status in ('draft', 'changes_requested', 'resubmitted')
    )
  );

-- Storage objects -----------------------------------------------------------
-- Readable when the participant owns the object or it backs a resource they
-- can see. Hub needs the row to render a filename and size before requesting
-- a signed URL.

drop policy if exists storage_objects_select_participant on public.storage_objects;
create policy storage_objects_select_participant on public.storage_objects
  for select
  using (
    deleted_at is null
    and (
      owner_profile_id = auth.uid()
      or exists (
        select 1 from public.digital_resources r
        where r.storage_object_id = storage_objects.id
      )
    )
  );

drop policy if exists storage_objects_insert_own on public.storage_objects;
create policy storage_objects_insert_own on public.storage_objects
  for insert
  with check (owner_profile_id = auth.uid() and uploaded_by = auth.uid());

-- Policies ------------------------------------------------------------------

drop policy if exists policy_documents_select_all on public.policy_documents;
create policy policy_documents_select_all on public.policy_documents
  for select to authenticated using (true);

drop policy if exists policy_acceptances_select_own on public.policy_acceptances;
create policy policy_acceptances_select_own on public.policy_acceptances
  for select using (profile_id = auth.uid());

drop policy if exists policy_acceptances_insert_own on public.policy_acceptances;
create policy policy_acceptances_insert_own on public.policy_acceptances
  for insert with check (profile_id = auth.uid());

-- Feedback (BR-009) ---------------------------------------------------------
--
-- Deliberately NOT a policy on public.feedback.
--
-- RLS filters rows, not columns. Any policy that let a participant select
-- their released feedback row would also expose feedback.private_note on that
-- same row - the reviewer's confidential assessment - to anyone who queries
-- the table directly instead of going through the app.
--
-- Instead participants get no access to the table at all, and read a
-- SECURITY DEFINER view that projects only the safe columns. The view also
-- resolves the reviewer's name, which a participant could not otherwise read
-- (profiles is self-or-admin only) and which Hub needs to say who reviewed
-- their work.

create or replace view public.participant_feedback
with (security_invoker = false) as
select
  f.id,
  f.submission_id,
  f.reviewer_id,
  coalesce(p.display_name, 'Bauhaven reviewer') as reviewer_name,
  f.visible_feedback,
  f.result,
  -- Always 'released' by the where clause below. Selected anyway so the Hub
  -- DTO can parse visibility from this view exactly as it would from the
  -- table, rather than special-casing a null.
  f.visibility,
  f.score,
  f.rubric_response,
  f.allow_resubmission,
  f.resubmission_due_at,
  f.released_at,
  -- Hub lists feedback by the task it belongs to. Reaching the title through
  -- PostgREST embedding would need select access on tasks and task_assignments
  -- from the feedback row; resolving it here keeps that surface closed.
  t.title as task_title,
  f.created_at,
  f.updated_at
from public.feedback f
join public.submissions s on s.id = f.submission_id
left join public.task_assignments ta on ta.id = s.task_assignment_id
left join public.tasks t on t.id = ta.task_id
left join public.profiles p on p.id = f.reviewer_id
where f.visibility = 'released'
  and f.released_at is not null
  and s.participant_id = auth.uid();

-- Assigned mentors ----------------------------------------------------------
--
-- Same constraint as feedback: profiles is self-or-admin, so a participant
-- cannot read their own mentor's name. Hub needs it on the programme screen.
-- A view scoped to the caller's enrolments exposes the mentor's name and
-- nothing else about that staff member.

create or replace view public.participant_enrolment_mentors
with (security_invoker = false) as
select
  e.id   as enrolment_id,
  e.mentor_id,
  coalesce(p.display_name, 'Your mentor') as mentor_name,
  p.avatar_path,
  true as is_primary
from public.enrolments e
join public.profiles p on p.id = e.mentor_id
where e.profile_id = auth.uid()
  and e.mentor_id is not null;

comment on view public.participant_enrolment_mentors is
  'Mentor name for the calling participant''s own enrolments. Exists because '
  'profiles is self-or-admin and Hub must still name the assigned mentor.';

revoke all on public.participant_enrolment_mentors from public, anon;
grant select on public.participant_enrolment_mentors to authenticated;

comment on view public.participant_feedback is
  'BR-009: released feedback for the calling participant. Omits private_note '
  'by construction - participants have no select grant on public.feedback.';

revoke all on public.participant_feedback from public, anon;
grant select on public.participant_feedback to authenticated;
