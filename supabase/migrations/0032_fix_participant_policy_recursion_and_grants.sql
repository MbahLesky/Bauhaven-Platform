-- Renumbered 2026-09-11: this was `0011_fix_participant_policy_recursion_and_grants.sql` on
-- MbahLesky/Bauhaven-admin `main` (see 0029 for why). "0009" below now means 0030. Already applied to
-- keyaahfksbfigcdbbuda - do not re-run it there.
--
-- Bauhaven - Fix two bugs introduced by 0009
--
-- Both were found by querying the deployed database; neither is visible by
-- reading the SQL alone.
--
--
-- BUG 1: permission denied for function is_enrolled_in_offering (42501)
--
-- 0009 revoked execute from public and granted only to `authenticated`. `anon`
-- is not `authenticated`, so an unauthenticated request that touched offerings,
-- cohorts, announcements, programme_milestones or attendance called the helper
-- and got 42501.
--
-- A policy expression that raises does not evaluate to false - it aborts the
-- whole query. So anonymous reads failed outright instead of returning no rows,
-- including reads an existing admin or public policy would have allowed.
--
-- Granting to anon is safe: these are SECURITY DEFINER but filter on
-- auth.uid(), which is null for anon, so they return false and disclose
-- nothing. private.is_self() has always been executable by anon, which is why
-- profiles never broke this way.
--
--
-- BUG 2: infinite recursion detected in policy (42P17)
--
-- 0009's tasks_select_participant policy read public.task_assignments inline.
-- The pre-existing task_assignments_select policy reads public.tasks. So:
--
--   tasks -> task_assignments -> tasks -> ...
--
-- Postgres evaluates the referenced table's policies during the subquery, so
-- the two policies called each other until the executor gave up.
--
-- That single cycle is why six tables failed: submissions, submission_files,
-- task_resources, digital_resources and storage_objects all reach tasks
-- transitively through their own policies.
--
-- The fix is to stop reading RLS-protected tables from inside a policy. Each
-- cross-table check below moves into a SECURITY DEFINER function, which
-- bypasses RLS on the tables it reads and therefore cannot re-enter the policy
-- that called it. This is the same technique 0009 already used for the
-- enrolment helpers; it simply was not applied to the task lookups.

-- Bug 1: grants ---------------------------------------------------------------

grant execute on function private.is_enrolled_in_offering(uuid) to anon;
grant execute on function private.is_enrolled_in_cohort(uuid) to anon;
grant execute on function private.owns_enrolment(uuid) to anon;

-- Bug 2: non-recursive helpers ------------------------------------------------

-- Does the caller hold a task assignment for this task? Reads task_assignments
-- and enrolments as the definer, so neither table's policy is evaluated.
create or replace function private.has_task_assignment(target_task_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.task_assignments ta
    join public.enrolments e on e.id = ta.enrolment_id
    where ta.task_id = target_task_id
      and e.profile_id = auth.uid()
  );
$$;

-- Is this task visible to the caller at all? Same rule as the tasks policy,
-- resolved without touching the policy. Used by every table that hangs off a
-- task, so the visibility rule stays defined in exactly one place.
create or replace function private.can_see_task(target_task_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.tasks t
    where t.id = target_task_id
      and t.status = 'published'
      and (
        private.has_task_assignment(t.id)
        or (t.offering_id is not null
            and private.is_enrolled_in_offering(t.offering_id))
        or (t.cohort_id is not null
            and private.is_enrolled_in_cohort(t.cohort_id))
      )
  );
$$;

create or replace function private.owns_submission(target_submission_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.submissions s
    where s.id = target_submission_id
      and s.participant_id = auth.uid()
  );
$$;

-- Is this storage object attached to a resource the caller may see?
create or replace function private.storage_object_is_visible(target_object_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.digital_resources r
    where r.storage_object_id = target_object_id
      and (
        r.visibility_scope_type = 'organisation'
        or (r.visibility_scope_type = 'offering'
            and private.is_enrolled_in_offering(r.visibility_scope_id))
        or (r.visibility_scope_type = 'cohort'
            and private.is_enrolled_in_cohort(r.visibility_scope_id))
        or exists (
          select 1 from public.task_resources tr
          where tr.resource_id = r.id
            and private.can_see_task(tr.task_id)
        )
      )
  );
$$;

-- Is this resource attached to a task the caller may see?
create or replace function private.resource_on_visible_task(target_resource_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.task_resources tr
    where tr.resource_id = target_resource_id
      and private.can_see_task(tr.task_id)
  );
$$;

revoke execute on function private.has_task_assignment(uuid) from public;
revoke execute on function private.can_see_task(uuid) from public;
revoke execute on function private.owns_submission(uuid) from public;
revoke execute on function private.storage_object_is_visible(uuid) from public;
revoke execute on function private.resource_on_visible_task(uuid) from public;

grant execute on function private.has_task_assignment(uuid) to authenticated, anon;
grant execute on function private.can_see_task(uuid) to authenticated, anon;
grant execute on function private.owns_submission(uuid) to authenticated, anon;
grant execute on function private.storage_object_is_visible(uuid) to authenticated, anon;
grant execute on function private.resource_on_visible_task(uuid) to authenticated, anon;

-- Bug 2: policies rebuilt without cross-table reads ---------------------------

-- FR-HUB-TASK-003 still holds: the published guard is inside can_see_task and
-- is re-stated here so the rule is visible at the policy.
drop policy if exists tasks_select_participant on public.tasks;
create policy tasks_select_participant on public.tasks
  for select
  using (
    status = 'published'
    and (
      private.has_task_assignment(id)
      or (offering_id is not null and private.is_enrolled_in_offering(offering_id))
      or (cohort_id is not null and private.is_enrolled_in_cohort(cohort_id))
    )
  );

drop policy if exists task_resources_select_participant on public.task_resources;
create policy task_resources_select_participant on public.task_resources
  for select
  using (private.can_see_task(task_id));

drop policy if exists digital_resources_select_participant on public.digital_resources;
create policy digital_resources_select_participant on public.digital_resources
  for select
  using (
    visibility_scope_type = 'organisation'
    or (visibility_scope_type = 'offering'
        and private.is_enrolled_in_offering(visibility_scope_id))
    or (visibility_scope_type = 'cohort'
        and private.is_enrolled_in_cohort(visibility_scope_id))
    or private.resource_on_visible_task(id)
  );

drop policy if exists submission_files_select_own on public.submission_files;
create policy submission_files_select_own on public.submission_files
  for select
  using (private.owns_submission(submission_id));

drop policy if exists submission_files_insert_own on public.submission_files;
create policy submission_files_insert_own on public.submission_files
  for insert
  with check (private.owns_submission(submission_id));

drop policy if exists storage_objects_select_participant on public.storage_objects;
create policy storage_objects_select_participant on public.storage_objects
  for select
  using (
    deleted_at is null
    and (
      owner_profile_id = auth.uid()
      or private.storage_object_is_visible(id)
    )
  );

-- Views -----------------------------------------------------------------------
-- Granted to anon as well so an unauthenticated read returns no rows rather
-- than "permission denied for view". Both views already filter on auth.uid(),
-- which is null for anon, so neither discloses anything.

grant select on public.participant_feedback to anon;
grant select on public.participant_enrolment_mentors to anon;
