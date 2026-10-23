-- Bauhaven Admin - governance v2.0
--
-- Aligns identity/RBAC with BauhavenDocs v2.0 (BAU-DB-002 section 6,
-- BAU-ADMIN-AUTH-001 sections 4-6). This supersedes the simpler role model
-- from migration 0002, applied only hours earlier in this same project -
-- safe to evolve in place rather than treat as "legacy" since nothing
-- outside this repo depends on it yet (one grant exists: the bootstrap
-- platform_admin, migrated below to super_admin).
--
-- Correction from 0002/approve-application v1: v2.0 does not model
-- participant/Hub access as a role grant at all - a participant's access
-- comes from having an active `enrolments` row, not a `roles` row (the
-- "Initial Role Catalogue" in BAU-ADMIN-AUTH-001 section 5 lists only the
-- nine staff/admin roles below; participants aren't in it). The 'learner'
-- role this repo's first governance pass granted on approval is removed -
-- see 0010_approve_application_v2 equivalent Edge Function update.

do $$
begin
  if not exists (select 1 from pg_type where typname = 'role_assignment_type') then
    create type public.role_assignment_type as enum ('permanent', 'temporary');
  end if;
  if not exists (select 1 from pg_type where typname = 'role_assignment_status') then
    create type public.role_assignment_status as enum ('pending', 'active', 'suspended', 'expired', 'revoked');
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- roles: rename keys to the v2.0 catalogue, add is_active
-- (BAU-DB-002 section 6.1 - missing from this repo's first draft).
-- ---------------------------------------------------------------------------
alter table public.roles add column if not exists is_active boolean not null default true;

update public.roles set code = 'super_admin', name = 'Super Admin',
  description = 'Highest approved platform governance.' where code = 'platform_admin';
update public.roles set code = 'programme_manager', name = 'Programme Manager',
  description = 'Assigned offerings, cohorts, participants, schedules and work.' where code = 'program_manager';
update public.roles set code = 'application_reviewer', name = 'Application Reviewer',
  description = 'Assigned application queues and decisions.' where code = 'reviewer';
update public.roles set code = 'mentor_supervisor', name = 'Mentor or Supervisor',
  description = 'Assigned participants, tasks, reviews, feedback, attendance and evaluations.' where code = 'mentor';

insert into public.roles (code, name, description) values
  ('organisation_admin', 'Organisation Admin', 'Broad organisation operations.'),
  ('internship_coordinator', 'Internship Coordinator', 'Assigned internship lifecycle, interns, tasks, submissions and attendance.'),
  ('auditor', 'Auditor', 'Read-only authorised records and audit evidence.')
on conflict (code) do nothing;

-- 'staff' and 'learner' are not in the v2.0 catalogue. Deactivate rather
-- than delete (is_active flag preserves FK-safety and history if anything
-- was ever granted); nothing currently holds either grant live.
update public.roles set is_active = false where code in ('staff', 'learner');

-- ---------------------------------------------------------------------------
-- user_roles -> user_role_assignments: rename in place and add the v2.0
-- lifecycle columns (assignment_type, valid_from/until, status, suspend/
-- revoke actor+reason, metadata). Safe rename: this table has exactly one
-- row at the time of writing (the bootstrap admin grant) and only this
-- repo's own code/RLS/Edge Function reference it.
-- ---------------------------------------------------------------------------
alter table public.user_roles rename to user_role_assignments;

alter table public.user_role_assignments
  add column if not exists assignment_type public.role_assignment_type not null default 'permanent';
alter table public.user_role_assignments
  add column if not exists valid_from timestamptz not null default now();
alter table public.user_role_assignments
  add column if not exists valid_until timestamptz;
alter table public.user_role_assignments
  add column if not exists status public.role_assignment_status not null default 'active';
alter table public.user_role_assignments
  add column if not exists suspended_at timestamptz;
alter table public.user_role_assignments
  add column if not exists suspended_by uuid references public.profiles (id);
alter table public.user_role_assignments
  add column if not exists revoked_by uuid references public.profiles (id);
alter table public.user_role_assignments
  add column if not exists revocation_reason text;
alter table public.user_role_assignments
  add column if not exists metadata jsonb not null default '{}'::jsonb;
alter table public.user_role_assignments
  add column if not exists updated_at timestamptz not null default now();
alter table public.user_role_assignments rename column granted_at to created_at_legacy;
update public.user_role_assignments set created_at_legacy = coalesce(created_at_legacy, now());
alter table public.user_role_assignments
  add column if not exists created_at timestamptz;
update public.user_role_assignments set created_at = coalesce(created_at, created_at_legacy, now());
alter table public.user_role_assignments alter column created_at set default now();
alter table public.user_role_assignments alter column created_at set not null;
alter table public.user_role_assignments drop column if exists created_at_legacy;

-- scope_type widened to the full v2.0 vocabulary ('platform' renamed to
-- 'organisation' to match; existing rows migrated). The old inline column
-- check from migration 0002 was auto-named `user_roles_scope_type_check`
-- (table name at creation time) - it must be dropped before the UPDATE
-- below, not after, or the update itself violates it.
alter table public.user_role_assignments drop constraint if exists user_roles_scope_id_required;
alter table public.user_role_assignments drop constraint if exists user_roles_scope_type_check;
update public.user_role_assignments set scope_type = 'organisation' where scope_type = 'platform';
alter table public.user_role_assignments drop constraint if exists user_role_assignments_scope_type_check;
alter table public.user_role_assignments
  add constraint user_role_assignments_scope_type_check
  check (scope_type in ('organisation', 'offering', 'cohort', 'project', 'content_domain', 'asset_domain'));
alter table public.user_role_assignments
  add constraint user_role_assignments_scope_id_required check (
    (scope_type = 'organisation' and scope_id is null)
    or (scope_type <> 'organisation' and scope_id is not null)
  );
alter table public.user_role_assignments
  add constraint user_role_assignments_valid_until_check check (valid_until is null or valid_until > valid_from);
alter table public.user_role_assignments
  add constraint user_role_assignments_temporary_check check (
    (assignment_type = 'temporary' and valid_until is not null) or assignment_type = 'permanent'
  );

drop trigger if exists user_role_assignments_set_updated_at on public.user_role_assignments;
create trigger user_role_assignments_set_updated_at
  before update on public.user_role_assignments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- role_assignment_events: append-only lifecycle history
-- (BAU-DB-002 section 6.7).
-- ---------------------------------------------------------------------------
create table if not exists public.role_assignment_events (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.user_role_assignments (id) on delete cascade,
  event_type text not null check (event_type in ('granted', 'activated', 'extended', 'suspended', 'reinstated', 'expired', 'revoked')),
  actor_id uuid references public.profiles (id),
  occurred_at timestamptz not null default now(),
  reason text,
  previous_values jsonb,
  new_values jsonb
);

create index if not exists role_assignment_events_assignment_id_idx
  on public.role_assignment_events (assignment_id, occurred_at desc);

create or replace function public.record_role_assignment_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.role_assignment_events (assignment_id, event_type, actor_id, reason, new_values)
    values (new.id, 'granted', new.granted_by, null, jsonb_build_object('status', new.status, 'role_id', new.role_id));
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
    insert into public.role_assignment_events (assignment_id, event_type, actor_id, reason, previous_values, new_values)
    values (
      new.id,
      case new.status
        when 'active' then case when old.status = 'suspended' then 'reinstated' else 'activated' end
        when 'suspended' then 'suspended'
        when 'expired' then 'expired'
        when 'revoked' then 'revoked'
        else 'activated'
      end,
      coalesce(new.suspended_by, new.revoked_by, auth.uid()),
      new.revocation_reason,
      jsonb_build_object('status', old.status),
      jsonb_build_object('status', new.status)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists user_role_assignments_record_change on public.user_role_assignments;
create trigger user_role_assignments_record_change
  after insert or update on public.user_role_assignments
  for each row execute function public.record_role_assignment_change();

-- ---------------------------------------------------------------------------
-- admin_invitations (BAU-DB-002 section 6.5). Distinct from the
-- participant-facing `invitations` table (migration 0005) - this one is for
-- inviting staff/administrators, never participants.
-- ---------------------------------------------------------------------------
create table if not exists public.admin_invitations (
  id uuid primary key default gen_random_uuid(),
  email citext not null,
  role_id uuid not null references public.roles (id),
  assignment_type public.role_assignment_type not null,
  scope_type text not null check (scope_type in ('organisation', 'offering', 'cohort', 'project', 'content_domain', 'asset_domain')),
  scope_id uuid,
  access_valid_from timestamptz not null default now(),
  access_valid_until timestamptz,
  token_hash text not null unique,
  status public.invitation_status not null default 'queued',
  issued_by uuid references public.profiles (id),
  issued_at timestamptz not null default now(),
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_user_id uuid references public.profiles (id),
  revoked_at timestamptz,
  revoked_by uuid references public.profiles (id),
  delivery_status text,
  provider_message_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint admin_invitations_scope_id_required check (
    (scope_type = 'organisation' and scope_id is null) or (scope_type <> 'organisation' and scope_id is not null)
  ),
  constraint admin_invitations_temporary_check check (
    (assignment_type = 'temporary' and access_valid_until is not null) or assignment_type = 'permanent'
  )
);

create index if not exists admin_invitations_email_idx on public.admin_invitations (lower(email::text));

drop trigger if exists admin_invitations_set_updated_at on public.admin_invitations;
create trigger admin_invitations_set_updated_at
  before update on public.admin_invitations
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- staff_profiles (BAU-DB-002 section 5.3) and access_reviews (section 6.6).
-- ---------------------------------------------------------------------------
create table if not exists public.staff_profiles (
  profile_id uuid primary key references public.profiles (id) on delete cascade,
  staff_code text unique,
  job_title text,
  department text,
  staff_type text check (staff_type in ('permanent', 'temporary', 'contractor') or staff_type is null),
  start_date date,
  end_date date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists staff_profiles_set_updated_at on public.staff_profiles;
create trigger staff_profiles_set_updated_at
  before update on public.staff_profiles
  for each row execute function public.set_updated_at();

create table if not exists public.access_reviews (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.user_role_assignments (id) on delete cascade,
  reviewed_by uuid references public.profiles (id),
  reviewed_at timestamptz not null default now(),
  decision text not null check (decision in ('retain', 'extend', 'suspend', 'revoke')),
  new_valid_until timestamptz,
  notes text
);

-- ---------------------------------------------------------------------------
-- Helper functions (BAU-DB-002 section 18), replacing 0002's simpler
-- is_admin()/has_permission(). Kept under the same names so RLS policies
-- and Edge Functions written against 0002 keep working; behaviour is now
-- scope- and validity-aware.
-- ---------------------------------------------------------------------------
create or replace function public.is_assignment_active(a public.user_role_assignments)
returns boolean
language sql
stable
as $$
  select a.status = 'active'
     and a.valid_from <= now()
     and (a.valid_until is null or a.valid_until > now());
$$;

create or replace function private.has_permission(
  p_code text,
  p_scope_type text default 'organisation',
  p_scope_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    where ura.user_id = auth.uid()
      and p.code = p_code
      and public.is_assignment_active(ura)
      and (
        ura.scope_type = 'organisation'
        or (ura.scope_type = p_scope_type and ura.scope_id = p_scope_id)
      )
  );
$$;

create or replace function public.is_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where ura.user_id = uid
      and public.is_assignment_active(ura)
      and r.code in ('super_admin', 'organisation_admin', 'programme_manager', 'internship_coordinator', 'application_reviewer', 'auditor')
  );
$$;

comment on function public.is_admin(uuid) is
  'UX convenience for "can open the admin console at all" - individual screens/actions must still call private.has_permission() with the specific permission+scope they need. RLS is the real boundary.';
