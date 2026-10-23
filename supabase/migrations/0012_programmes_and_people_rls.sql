-- Bauhaven Admin - RLS for Programmes/Cohorts/People (Phase 3)

alter table public.cohort_staff_assignments enable row level security;
alter table public.programme_milestones enable row level security;
alter table public.participant_profiles enable row level security;

-- offerings/cohorts already have RLS + a select policy from migration 0007
-- (admin-only read). This adds the write policies now that a CRUD UI exists.
drop policy if exists offerings_write on public.offerings;
create policy offerings_write on public.offerings
  for all
  using (private.has_permission('programmes.manage'))
  with check (private.has_permission('programmes.manage'));

-- Checks both offering-scoped and cohort-scoped grants: a coordinator
-- scoped directly to one cohort (scope_type='cohort', scope_id=cohorts.id)
-- and one scoped to its parent offering should both be able to manage it.
drop policy if exists cohorts_write on public.cohorts;
create policy cohorts_write on public.cohorts
  for all
  using (
    private.has_permission('cohorts.manage', 'offering', offering_id)
    or private.has_permission('cohorts.manage', 'cohort', id)
  )
  with check (
    private.has_permission('cohorts.manage', 'offering', offering_id)
    or private.has_permission('cohorts.manage', 'cohort', id)
  );

drop policy if exists cohort_staff_assignments_select on public.cohort_staff_assignments;
create policy cohort_staff_assignments_select on public.cohort_staff_assignments
  for select
  using (public.is_admin(auth.uid()) or staff_profile_id = auth.uid());

drop policy if exists cohort_staff_assignments_write on public.cohort_staff_assignments;
create policy cohort_staff_assignments_write on public.cohort_staff_assignments
  for insert
  with check (private.has_permission('cohorts.manage'));

drop policy if exists cohort_staff_assignments_delete on public.cohort_staff_assignments;
create policy cohort_staff_assignments_delete on public.cohort_staff_assignments
  for delete
  using (private.has_permission('cohorts.manage'));

drop policy if exists programme_milestones_select on public.programme_milestones;
create policy programme_milestones_select on public.programme_milestones
  for select using (public.is_admin(auth.uid()));

drop policy if exists programme_milestones_write on public.programme_milestones;
create policy programme_milestones_write on public.programme_milestones
  for all
  using (private.has_permission('programmes.manage') or private.has_permission('cohorts.manage'))
  with check (private.has_permission('programmes.manage') or private.has_permission('cohorts.manage'));

drop policy if exists participant_profiles_select on public.participant_profiles;
create policy participant_profiles_select on public.participant_profiles
  for select using (private.is_self(profile_id) or private.has_permission('participants.read'));

drop policy if exists participant_profiles_upsert_self on public.participant_profiles;
create policy participant_profiles_upsert_self on public.participant_profiles
  for insert with check (private.is_self(profile_id));

drop policy if exists participant_profiles_update on public.participant_profiles;
create policy participant_profiles_update on public.participant_profiles
  for update
  using (private.is_self(profile_id) or private.has_permission('participants.manage'))
  with check (private.is_self(profile_id) or private.has_permission('participants.manage'));
