-- Bauhaven Admin - governance v2.0 permissions and RLS
--
-- Permission keys follow BAU-DB-002 section 6.2's example list. Some
-- overlap with this repo's existing `applications.decide` (migration 0002),
-- which stays as-is (already wired into RLS + the approve-application Edge
-- Function) rather than being rewired in the same pass as the table rename
-- above - noted here as a follow-up consolidation, not done blindly under
-- time pressure alongside a live-database rename.

-- role_permissions had no created_by column (added here to match
-- BAU-DB-002 section 6.3; nullable since historic/seed rows have no actor).
alter table public.role_permissions add column if not exists created_by uuid references public.profiles (id);

-- permissions had no domain/risk_level columns (added here to match
-- BAU-DB-002 section 6.2).
alter table public.permissions add column if not exists domain text;
alter table public.permissions add column if not exists risk_level text check (risk_level in ('low', 'medium', 'high', 'critical') or risk_level is null);

insert into public.permissions (code, domain, name, description, risk_level) values
  ('applications.read', 'admissions', 'Read applications', 'View admissions applications and history.', 'low'),
  ('applications.review', 'admissions', 'Review applications', 'Add notes, request clarification, assign reviewers.', 'medium'),
  ('applications.approve', 'admissions', 'Approve applications', 'Approve, reject or waitlist an application.', 'high'),
  ('participants.read', 'people', 'Read participants', 'View participant directory and profiles within scope.', 'low'),
  ('participants.manage', 'people', 'Manage participants', 'Suspend, archive, transfer participant enrolments.', 'high'),
  ('programmes.manage', 'programmes', 'Manage programmes', 'Create/edit offerings.', 'medium'),
  ('cohorts.manage', 'programmes', 'Manage cohorts', 'Create/edit cohorts and cohort staff assignments.', 'medium'),
  ('tasks.create', 'learning', 'Create tasks', 'Create and edit tasks/projects.', 'medium'),
  ('tasks.assign', 'learning', 'Assign tasks', 'Assign tasks to enrolments/cohorts.', 'medium'),
  ('submissions.review', 'learning', 'Review submissions', 'View and review participant submissions.', 'medium'),
  ('feedback.release', 'learning', 'Release feedback', 'Release participant-visible feedback.', 'medium'),
  ('attendance.record', 'attendance', 'Record attendance', 'Create sessions and mark attendance.', 'medium'),
  ('attendance.correct', 'attendance', 'Correct attendance', 'Correct an existing attendance record with a reason.', 'high'),
  ('cms.publish', 'website', 'Publish Website content', 'Publish/unpublish Website CMS content.', 'high'),
  ('assets.manage', 'resources', 'Manage assets', 'Manage physical/digital resource inventory and assignments.', 'medium'),
  ('roles.assign', 'governance', 'Assign roles', 'Invite administrators and grant role assignments.', 'critical'),
  ('roles.revoke', 'governance', 'Revoke roles', 'Suspend or revoke role assignments.', 'critical'),
  ('audit.read', 'governance', 'Read audit log', 'View audit log and access review history.', 'medium'),
  ('settings.manage', 'governance', 'Manage settings', 'Manage organisation-level settings.', 'high')
on conflict (code) do nothing;

-- role_permissions mapping. Judgment call documented here: organisation_admin
-- gets every operational permission but not roles.assign/roles.revoke -
-- those stay super_admin-only, consistent with BR-006 "no self-escalation"
-- and section 5's "a title alone does not authorise access" - governance
-- itself is deliberately the narrowest-held capability.
insert into public.role_permissions (role_id, permission_id, created_by)
select r.id, p.id, null
from public.roles r
join public.permissions p on (
  (r.code = 'super_admin') or
  (r.code = 'organisation_admin' and p.code not in ('roles.assign', 'roles.revoke')) or
  (r.code in ('programme_manager', 'internship_coordinator') and p.code in (
    'applications.read', 'applications.review', 'applications.approve',
    'participants.read', 'participants.manage', 'programmes.manage', 'cohorts.manage',
    'tasks.create', 'tasks.assign', 'submissions.review', 'feedback.release',
    'attendance.record', 'attendance.correct'
  )) or
  (r.code = 'application_reviewer' and p.code in ('applications.read', 'applications.review', 'participants.read')) or
  (r.code = 'mentor_supervisor' and p.code in ('participants.read', 'tasks.assign', 'submissions.review', 'feedback.release', 'attendance.record', 'attendance.correct')) or
  (r.code = 'content_manager' and p.code = 'cms.publish') or
  (r.code = 'asset_manager' and p.code = 'assets.manage') or
  (r.code = 'auditor' and p.code = 'audit.read')
)
on conflict do nothing;

-- Also grant the pre-existing applications.decide/applications.notes.manage
-- to the roles that replace program_manager/reviewer, so existing RLS keeps
-- working for the renamed roles.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on (
  (r.code in ('super_admin', 'organisation_admin', 'programme_manager', 'internship_coordinator') and p.code in ('applications.decide', 'applications.notes.manage')) or
  (r.code = 'application_reviewer' and p.code = 'applications.notes.manage')
)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- get_my_active_roles(): single source of truth for "which roles am I
-- currently allowed to act as", reusing is_assignment_active() rather than
-- duplicating the valid_from/valid_until/status logic in every client.
-- ---------------------------------------------------------------------------
create or replace function public.get_my_active_roles()
returns table (role_code text, scope_type text, scope_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select r.code, ura.scope_type, ura.scope_id
  from public.user_role_assignments ura
  join public.roles r on r.id = ura.role_id
  where ura.user_id = auth.uid()
    and public.is_assignment_active(ura);
$$;

-- ---------------------------------------------------------------------------
-- RLS for the new tables.
-- ---------------------------------------------------------------------------
alter table public.admin_invitations enable row level security;
alter table public.role_assignment_events enable row level security;
alter table public.staff_profiles enable row level security;
alter table public.access_reviews enable row level security;

drop policy if exists admin_invitations_select on public.admin_invitations;
create policy admin_invitations_select on public.admin_invitations
  for select using (private.has_permission('roles.assign'));

-- No client INSERT/UPDATE/DELETE policy: admin invitations are only ever
-- created/accepted through the invite-administrator /
-- accept-admin-invitation Edge Functions (service role).

drop policy if exists role_assignment_events_select on public.role_assignment_events;
create policy role_assignment_events_select on public.role_assignment_events
  for select using (private.has_permission('roles.assign') or private.has_permission('audit.read'));

drop policy if exists staff_profiles_select on public.staff_profiles;
create policy staff_profiles_select on public.staff_profiles
  for select using (private.is_self(profile_id) or public.is_admin(auth.uid()));

drop policy if exists staff_profiles_update on public.staff_profiles;
create policy staff_profiles_update on public.staff_profiles
  for update using (private.is_self(profile_id) or private.has_permission('roles.assign'))
  with check (private.is_self(profile_id) or private.has_permission('roles.assign'));

-- A staff member completes their own profile after accepting an invitation
-- (FR-ADM-AUTH-005) - insert is allowed for the row's own owner.
drop policy if exists staff_profiles_insert_self on public.staff_profiles;
create policy staff_profiles_insert_self on public.staff_profiles
  for insert with check (private.is_self(profile_id));

drop policy if exists access_reviews_select on public.access_reviews;
create policy access_reviews_select on public.access_reviews
  for select using (private.has_permission('roles.assign') or private.has_permission('audit.read'));

-- user_role_assignments already has RLS + a select policy from migration
-- 0007 (under the pre-rename table name - policies follow table renames
-- automatically in Postgres, no action needed). No client
-- INSERT/UPDATE/DELETE policy existed before and still doesn't: grants,
-- suspensions and revocations only happen through Edge Functions using the
-- service role.
