-- Bauhaven Admin - RLS for Phase 5 (Tasks, Projects, Assignments,
-- Submissions, Feedback). Scoped by offering/cohort from the start using
-- private.has_permission(code, scope_type, scope_id) - the exact pattern
-- migration 0014 had to retrofit onto Admissions/People after finding it
-- missing there; built correctly here the first time per BR-002 ("a user
-- cannot assign work outside their scopes" - Part D of the integration
-- prompt says this explicitly).
--
-- Submissions/feedback participant-self policies are included now (for
-- Hub to use once it exists) but intentionally minimal: feedback's
-- `private_note` column has no column-level masking here, so participant
-- SELECT on feedback is deliberately NOT enabled yet - only staff can read
-- feedback rows in this pass. Enabling participant-visible feedback needs
-- either a view that omits private_note or a second table split, to be
-- done alongside the actual Hub build, not guessed at here.

alter table public.learning_projects enable row level security;
alter table public.tasks enable row level security;
alter table public.task_assignments enable row level security;
alter table public.submissions enable row level security;
alter table public.feedback enable row level security;

-- projects ------------------------------------------------------------------
drop policy if exists learning_projects_select_scoped on public.learning_projects;
create policy learning_projects_select_scoped on public.learning_projects
  for select
  using (
    (offering_id is not null and (
      private.has_permission('tasks.create', 'offering', offering_id)
      or private.has_permission('tasks.assign', 'offering', offering_id)
      or private.has_permission('submissions.review', 'offering', offering_id)
    ))
    or (cohort_id is not null and (
      private.has_permission('tasks.create', 'cohort', cohort_id)
      or private.has_permission('tasks.assign', 'cohort', cohort_id)
      or private.has_permission('submissions.review', 'cohort', cohort_id)
    ))
  );

drop policy if exists learning_projects_write_scoped on public.learning_projects;
create policy learning_projects_write_scoped on public.learning_projects
  for all
  using (
    (offering_id is not null and private.has_permission('tasks.create', 'offering', offering_id))
    or (cohort_id is not null and private.has_permission('tasks.create', 'cohort', cohort_id))
  )
  with check (
    (offering_id is not null and private.has_permission('tasks.create', 'offering', offering_id))
    or (cohort_id is not null and private.has_permission('tasks.create', 'cohort', cohort_id))
  );

-- tasks -----------------------------------------------------------------
drop policy if exists tasks_select_scoped on public.tasks;
create policy tasks_select_scoped on public.tasks
  for select
  using (
    (offering_id is not null and (
      private.has_permission('tasks.create', 'offering', offering_id)
      or private.has_permission('tasks.assign', 'offering', offering_id)
      or private.has_permission('submissions.review', 'offering', offering_id)
    ))
    or (cohort_id is not null and (
      private.has_permission('tasks.create', 'cohort', cohort_id)
      or private.has_permission('tasks.assign', 'cohort', cohort_id)
      or private.has_permission('submissions.review', 'cohort', cohort_id)
    ))
    or (project_id is not null and exists (
      select 1 from public.learning_projects p where p.id = tasks.project_id
        and (
          (p.offering_id is not null and private.has_permission('tasks.create', 'offering', p.offering_id))
          or (p.cohort_id is not null and private.has_permission('tasks.create', 'cohort', p.cohort_id))
        )
    ))
  );

drop policy if exists tasks_write_scoped on public.tasks;
create policy tasks_write_scoped on public.tasks
  for all
  using (
    (offering_id is not null and private.has_permission('tasks.create', 'offering', offering_id))
    or (cohort_id is not null and private.has_permission('tasks.create', 'cohort', cohort_id))
    or (project_id is not null and exists (
      select 1 from public.learning_projects p where p.id = tasks.project_id
        and (
          (p.offering_id is not null and private.has_permission('tasks.create', 'offering', p.offering_id))
          or (p.cohort_id is not null and private.has_permission('tasks.create', 'cohort', p.cohort_id))
        )
    ))
  )
  with check (
    (offering_id is not null and private.has_permission('tasks.create', 'offering', offering_id))
    or (cohort_id is not null and private.has_permission('tasks.create', 'cohort', cohort_id))
    or (project_id is not null and exists (
      select 1 from public.learning_projects p where p.id = tasks.project_id
        and (
          (p.offering_id is not null and private.has_permission('tasks.create', 'offering', p.offering_id))
          or (p.cohort_id is not null and private.has_permission('tasks.create', 'cohort', p.cohort_id))
        )
    ))
  );

-- task_assignments --------------------------------------------------------
drop policy if exists task_assignments_select on public.task_assignments;
create policy task_assignments_select on public.task_assignments
  for select
  using (
    reviewer_id = auth.uid()
    or exists (select 1 from public.enrolments e where e.id = task_assignments.enrolment_id and e.profile_id = auth.uid())
    or exists (
      select 1 from public.tasks t where t.id = task_assignments.task_id
        and (
          (t.offering_id is not null and (
            private.has_permission('tasks.assign', 'offering', t.offering_id)
            or private.has_permission('submissions.review', 'offering', t.offering_id)
          ))
          or (t.cohort_id is not null and (
            private.has_permission('tasks.assign', 'cohort', t.cohort_id)
            or private.has_permission('submissions.review', 'cohort', t.cohort_id)
          ))
        )
    )
  );

drop policy if exists task_assignments_write on public.task_assignments;
create policy task_assignments_write on public.task_assignments
  for all
  using (
    exists (
      select 1 from public.tasks t where t.id = task_assignments.task_id
        and (
          (t.offering_id is not null and private.has_permission('tasks.assign', 'offering', t.offering_id))
          or (t.cohort_id is not null and private.has_permission('tasks.assign', 'cohort', t.cohort_id))
        )
    )
  )
  with check (
    exists (
      select 1 from public.tasks t where t.id = task_assignments.task_id
        and (
          (t.offering_id is not null and private.has_permission('tasks.assign', 'offering', t.offering_id))
          or (t.cohort_id is not null and private.has_permission('tasks.assign', 'cohort', t.cohort_id))
        )
    )
  );

-- submissions -------------------------------------------------------------
-- Participant self-service policies are included for Hub to use once it
-- exists - harmless today since no client calls them yet.
drop policy if exists submissions_select on public.submissions;
create policy submissions_select on public.submissions
  for select
  using (
    participant_id = auth.uid()
    or exists (
      select 1 from public.task_assignments ta join public.tasks t on t.id = ta.task_id
      where ta.id = submissions.task_assignment_id
        and (
          ta.reviewer_id = auth.uid()
          or (t.offering_id is not null and private.has_permission('submissions.review', 'offering', t.offering_id))
          or (t.cohort_id is not null and private.has_permission('submissions.review', 'cohort', t.cohort_id))
        )
    )
  );

drop policy if exists submissions_insert_self on public.submissions;
create policy submissions_insert_self on public.submissions
  for insert
  with check (private.is_self(participant_id));

drop policy if exists submissions_update_own_draft on public.submissions;
create policy submissions_update_own_draft on public.submissions
  for update
  using (private.is_self(participant_id) and status in ('draft', 'changes_requested', 'resubmitted'))
  with check (private.is_self(participant_id));

-- feedback ------------------------------------------------------------------
-- Staff-only for now - see the header comment on why participant SELECT
-- isn't enabled in this pass.
drop policy if exists feedback_select_staff on public.feedback;
create policy feedback_select_staff on public.feedback
  for select
  using (
    reviewer_id = auth.uid()
    or exists (
      select 1 from public.submissions s
      join public.task_assignments ta on ta.id = s.task_assignment_id
      join public.tasks t on t.id = ta.task_id
      where s.id = feedback.submission_id
        and (
          (t.offering_id is not null and private.has_permission('submissions.review', 'offering', t.offering_id))
          or (t.cohort_id is not null and private.has_permission('submissions.review', 'cohort', t.cohort_id))
        )
    )
  );

drop policy if exists feedback_write_staff on public.feedback;
create policy feedback_write_staff on public.feedback
  for all
  using (
    exists (
      select 1 from public.submissions s
      join public.task_assignments ta on ta.id = s.task_assignment_id
      join public.tasks t on t.id = ta.task_id
      where s.id = feedback.submission_id
        and (
          (t.offering_id is not null and (
            private.has_permission('submissions.review', 'offering', t.offering_id)
            or private.has_permission('feedback.release', 'offering', t.offering_id)
          ))
          or (t.cohort_id is not null and (
            private.has_permission('submissions.review', 'cohort', t.cohort_id)
            or private.has_permission('feedback.release', 'cohort', t.cohort_id)
          ))
        )
    )
  )
  with check (
    exists (
      select 1 from public.submissions s
      join public.task_assignments ta on ta.id = s.task_assignment_id
      join public.tasks t on t.id = ta.task_id
      where s.id = feedback.submission_id
        and (
          (t.offering_id is not null and (
            private.has_permission('submissions.review', 'offering', t.offering_id)
            or private.has_permission('feedback.release', 'offering', t.offering_id)
          ))
          or (t.cohort_id is not null and (
            private.has_permission('submissions.review', 'cohort', t.cohort_id)
            or private.has_permission('feedback.release', 'cohort', t.cohort_id)
          ))
        )
    )
  );
