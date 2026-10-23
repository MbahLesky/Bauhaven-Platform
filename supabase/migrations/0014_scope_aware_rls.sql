-- Bauhaven Admin - close a class of RLS gaps found while starting Phase 4
--
-- BR-002 / BAU-UML section 11: a temporary coordinator/mentor scoped to one
-- offering/cohort/project must not see or act on data outside that scope,
-- and this must be enforced by RLS, not just UI hiding. Several policies
-- written in migrations 0007/0012/0013 called private.has_permission(code)
-- with NO scope arguments. Per that function's definition (migration 0009),
-- omitting the scope arguments defaults to p_scope_type='organisation' with
-- a null scope_id, which only ever matches an organisation-scoped
-- assignment. Net effect: those policies were accidentally organisation-
-- admin-only - an offering-scoped programme_manager could not decide their
-- own applications, manage their own offering, or suspend a participant in
-- their own cohort. This migration passes the row's actual offering/cohort
-- id through to has_permission() so scoped grants work as designed, and
-- narrows applications/enrolments/related-table SELECT from a blanket
-- public.is_admin() check to the same scope-checked permission.

-- applications --------------------------------------------------------------
drop policy if exists applications_select_admin on public.applications;
create policy applications_select_scoped on public.applications
  for select
  using (private.has_permission('applications.read', 'offering', offering_id));

drop policy if exists applications_update_decision on public.applications;
create policy applications_update_decision_scoped on public.applications
  for update
  using (private.has_permission('applications.decide', 'offering', offering_id))
  with check (private.has_permission('applications.decide', 'offering', offering_id));

drop policy if exists application_status_history_select_admin on public.application_status_history;
create policy application_status_history_select_scoped on public.application_status_history
  for select
  using (
    exists (
      select 1 from public.applications a
      where a.id = application_status_history.application_id
        and private.has_permission('applications.read', 'offering', a.offering_id)
    )
  );

drop policy if exists application_approvals_select_admin on public.application_approvals;
create policy application_approvals_select_scoped on public.application_approvals
  for select
  using (
    exists (
      select 1 from public.applications a
      where a.id = application_approvals.application_id
        and private.has_permission('applications.read', 'offering', a.offering_id)
    )
  );

drop policy if exists invitations_select_admin on public.invitations;
create policy invitations_select_scoped on public.invitations
  for select
  using (
    exists (
      select 1 from public.applications a
      where a.id = invitations.application_id
        and private.has_permission('applications.read', 'offering', a.offering_id)
    )
  );

drop policy if exists application_reviews_select_admin on public.application_reviews;
create policy application_reviews_select_scoped on public.application_reviews
  for select
  using (
    exists (
      select 1 from public.applications a
      where a.id = application_reviews.application_id
        and private.has_permission('applications.read', 'offering', a.offering_id)
    )
  );

drop policy if exists application_reviews_insert on public.application_reviews;
create policy application_reviews_insert_scoped on public.application_reviews
  for insert
  with check (
    reviewer_id = auth.uid()
    and exists (
      select 1 from public.applications a
      where a.id = application_reviews.application_id
        and private.has_permission('applications.notes.manage', 'offering', a.offering_id)
    )
  );

-- enrolments / participants --------------------------------------------------
drop policy if exists enrolments_select_admin_or_related on public.enrolments;
create policy enrolments_select_scoped_or_related on public.enrolments
  for select
  using (
    private.has_permission('participants.read', 'offering', offering_id)
    or (cohort_id is not null and private.has_permission('participants.read', 'cohort', cohort_id))
    or mentor_id = auth.uid()
    or profile_id = auth.uid()
  );

drop policy if exists enrolment_status_history_select on public.enrolment_status_history;
create policy enrolment_status_history_select_scoped on public.enrolment_status_history
  for select
  using (
    exists (
      select 1 from public.enrolments e
      where e.id = enrolment_status_history.enrolment_id
        and (
          private.has_permission('participants.read', 'offering', e.offering_id)
          or (e.cohort_id is not null and private.has_permission('participants.read', 'cohort', e.cohort_id))
          or e.mentor_id = auth.uid()
          or e.profile_id = auth.uid()
        )
    )
  );

-- migration 0013's suspend/reactivate policy had the same unscoped-call bug.
drop policy if exists enrolments_update_participant_management on public.enrolments;
create policy enrolments_update_participant_management_scoped on public.enrolments
  for update
  using (
    private.has_permission('participants.manage', 'offering', offering_id)
    or (cohort_id is not null and private.has_permission('participants.manage', 'cohort', cohort_id))
  )
  with check (
    private.has_permission('participants.manage', 'offering', offering_id)
    or (cohort_id is not null and private.has_permission('participants.manage', 'cohort', cohort_id))
  );

-- offerings/cohorts/milestones/staff-assignments -----------------------------
-- Creating a brand-new offering can't be scope-checked against its own id
-- (it doesn't exist yet), so that stays organisation-wide-only by design -
-- split into a dedicated INSERT policy plus a scoped UPDATE/DELETE policy
-- (an offering-scoped programme_manager manages the offering they were
-- granted, but cannot create sibling offerings for themselves).
drop policy if exists offerings_write on public.offerings;

drop policy if exists offerings_insert on public.offerings;
create policy offerings_insert on public.offerings
  for insert
  with check (private.has_permission('programmes.manage', 'organisation', null));

drop policy if exists offerings_update_delete on public.offerings;
create policy offerings_update_delete on public.offerings
  for update
  using (private.has_permission('programmes.manage', 'offering', id))
  with check (private.has_permission('programmes.manage', 'offering', id));

drop policy if exists offerings_delete on public.offerings;
create policy offerings_delete on public.offerings
  for delete
  using (private.has_permission('programmes.manage', 'offering', id));

drop policy if exists cohort_staff_assignments_write on public.cohort_staff_assignments;
create policy cohort_staff_assignments_write_scoped on public.cohort_staff_assignments
  for insert
  with check (
    private.has_permission('cohorts.manage', 'cohort', cohort_id)
    or exists (
      select 1 from public.cohorts c
      where c.id = cohort_staff_assignments.cohort_id
        and private.has_permission('cohorts.manage', 'offering', c.offering_id)
    )
  );

drop policy if exists cohort_staff_assignments_delete on public.cohort_staff_assignments;
create policy cohort_staff_assignments_delete_scoped on public.cohort_staff_assignments
  for delete
  using (
    private.has_permission('cohorts.manage', 'cohort', cohort_id)
    or exists (
      select 1 from public.cohorts c
      where c.id = cohort_staff_assignments.cohort_id
        and private.has_permission('cohorts.manage', 'offering', c.offering_id)
    )
  );

drop policy if exists programme_milestones_write on public.programme_milestones;
create policy programme_milestones_write_scoped on public.programme_milestones
  for all
  using (
    (offering_id is not null and private.has_permission('programmes.manage', 'offering', offering_id))
    or (cohort_id is not null and private.has_permission('cohorts.manage', 'cohort', cohort_id))
    or (
      cohort_id is not null
      and exists (
        select 1 from public.cohorts c
        where c.id = programme_milestones.cohort_id
          and private.has_permission('cohorts.manage', 'offering', c.offering_id)
      )
    )
  )
  with check (
    (offering_id is not null and private.has_permission('programmes.manage', 'offering', offering_id))
    or (cohort_id is not null and private.has_permission('cohorts.manage', 'cohort', cohort_id))
    or (
      cohort_id is not null
      and exists (
        select 1 from public.cohorts c
        where c.id = programme_milestones.cohort_id
          and private.has_permission('cohorts.manage', 'offering', c.offering_id)
      )
    )
  );

drop policy if exists participant_profiles_select on public.participant_profiles;
create policy participant_profiles_select_scoped on public.participant_profiles
  for select
  using (
    private.is_self(profile_id)
    or exists (
      select 1 from public.enrolments e
      where e.profile_id = participant_profiles.profile_id
        and (
          private.has_permission('participants.read', 'offering', e.offering_id)
          or (e.cohort_id is not null and private.has_permission('participants.read', 'cohort', e.cohort_id))
        )
    )
  );

drop policy if exists participant_profiles_update on public.participant_profiles;
create policy participant_profiles_update_scoped on public.participant_profiles
  for update
  using (
    private.is_self(profile_id)
    or exists (
      select 1 from public.enrolments e
      where e.profile_id = participant_profiles.profile_id
        and (
          private.has_permission('participants.manage', 'offering', e.offering_id)
          or (e.cohort_id is not null and private.has_permission('participants.manage', 'cohort', e.cohort_id))
        )
    )
  )
  with check (
    private.is_self(profile_id)
    or exists (
      select 1 from public.enrolments e
      where e.profile_id = participant_profiles.profile_id
        and (
          private.has_permission('participants.manage', 'offering', e.offering_id)
          or (e.cohort_id is not null and private.has_permission('participants.manage', 'cohort', e.cohort_id))
        )
    )
  );
