-- Bauhaven Admin - identity and scoped RBAC
--
-- Role codes (platform_admin, program_manager, reviewer, mentor, staff,
-- content_manager, asset_manager, learner) match the literal DB role codes
-- found in the platform's RLS/Permission-Matrix technical document - not
-- this repo's own earlier invented names (super_admin/admissions_admin/
-- participant), which have been dropped in favour of the shared vocabulary
-- every Bauhaven app is expected to read from the same `roles` table.

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text not null default '',
  email citext not null,
  phone text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.profiles is 'Shared Bauhaven platform user profile, keyed by auth.users.id. One canonical profile per person (04_BAUHAVEN_DATABASE_SCHEMA.md section 4.1).';

-- `profiles` already existed live before this migration (created via the
-- Supabase dashboard, with its own `role text not null` and `u_code text
-- not null unique` - see the note further down). The CREATE TABLE above is
-- therefore a no-op there, which means `status`/`profile_completed_at`
-- would silently never get added without these explicit ALTERs - the same
-- bug class as applications.created_at in migration 0004.
alter table public.profiles add column if not exists status public.profile_status not null default 'pending';
alter table public.profiles add column if not exists profile_completed_at timestamptz;

-- The live `created_at` column (NOT NULL, no default) predates this
-- migration too - without this, handle_new_auth_user()'s INSERT (which
-- doesn't specify created_at) fails with a not-null violation on every
-- signup/invite.
alter table public.profiles alter column created_at set default now();

create unique index if not exists profiles_email_unique on public.profiles (email);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

-- The live `profiles` table (created before this migration existed, via the
-- Supabase dashboard - see supabase/README.md) already has `role text not
-- null` and `u_code text not null unique` with no defaults, columns this
-- migration's own `add column if not exists` calls above leave untouched
-- since they already exist. The insert below must satisfy both or every
-- new signup fails with a not-null violation. `role` defaults to
-- 'applicant' (nothing in bauhaven-website or bauhaven_ft's code reads this
-- column, so no existing convention to match); `u_code` is derived
-- deterministically from the new user's id so it's always unique.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, email, status, role, u_code)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(new.email, ''),
    'pending',
    'applicant',
    substr(replace(new.id::text, '-', ''), 1, 8)
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();

-- ---------------------------------------------------------------------------
-- roles / permissions / role_permissions / user_roles
-- ---------------------------------------------------------------------------
create table if not exists public.roles (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text not null default '',
  is_system boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.roles (code, name, description) values
  ('platform_admin', 'Platform Administrator', 'Full administrative access to every Bauhaven Admin module.'),
  ('program_manager', 'Program Manager', 'Manages applications, offerings, cohorts and the approval workflow.'),
  ('reviewer', 'Application Reviewer', 'Can view and comment on applications but not decide them.'),
  ('mentor', 'Mentor', 'Assigned to enrolments/cohorts as a mentor.'),
  ('staff', 'Staff', 'General staff access, scoped by future permission grants.'),
  ('content_manager', 'Content Manager', 'Manages public website content (out of MVP scope, seeded for forward compatibility).'),
  ('asset_manager', 'Asset Manager', 'Manages physical/digital resources (out of MVP scope, seeded for forward compatibility).'),
  ('learner', 'Learner', 'An approved applicant with a Hub account.')
on conflict (code) do nothing;

create table if not exists public.permissions (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text not null default '',
  created_at timestamptz not null default now()
);

insert into public.permissions (code, name, description) values
  ('applications.view', 'View applications', 'Read admissions applications and their history.'),
  ('applications.decide', 'Decide applications', 'Approve, reject, waitlist or request clarification on an application.'),
  ('applications.notes.manage', 'Manage application notes', 'Add internal reviewer notes to an application.'),
  ('roles.manage', 'Manage roles', 'Grant or revoke platform roles.')
on conflict (code) do nothing;

create table if not exists public.role_permissions (
  role_id uuid not null references public.roles (id) on delete cascade,
  permission_id uuid not null references public.permissions (id) on delete cascade,
  primary key (role_id, permission_id)
);

insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on (
  (r.code = 'platform_admin') or
  (r.code = 'program_manager' and p.code in ('applications.view', 'applications.decide', 'applications.notes.manage')) or
  (r.code = 'reviewer' and p.code in ('applications.view', 'applications.notes.manage'))
)
on conflict do nothing;

create table if not exists public.user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  role_id uuid not null references public.roles (id) on delete restrict,
  scope_type text not null default 'platform' check (scope_type in ('platform', 'offering', 'cohort')),
  scope_id uuid,
  granted_by uuid references public.profiles (id),
  granted_at timestamptz not null default now(),
  revoked_at timestamptz,
  constraint user_roles_scope_id_required check (
    (scope_type = 'platform' and scope_id is null) or
    (scope_type <> 'platform' and scope_id is not null)
  )
);

-- Only one *active* grant of a given role/scope per user (04_BAUHAVEN_DATABASE_SCHEMA.md
-- section 4.5: "Unique active grants must prevent duplicate role assignments").
create unique index if not exists user_roles_active_unique
  on public.user_roles (user_id, role_id, scope_type, coalesce(scope_id, '00000000-0000-0000-0000-000000000000'))
  where revoked_at is null;

create index if not exists user_roles_user_id_idx on public.user_roles (user_id) where revoked_at is null;

-- ---------------------------------------------------------------------------
-- private.has_permission / private.is_self
--
-- Verbatim pattern from the platform's RLS/Permission-Matrix technical
-- document: resolves user_roles -> roles -> role_permissions -> permissions,
-- honouring scope (a program_manager granted only on one offering/cohort
-- does not get platform-wide access) - see master spec IAM-007 equivalent
-- ("Mentors and staff SHALL access only assigned programmes/cohorts... unless
-- granted broader permission").
-- ---------------------------------------------------------------------------
create or replace function private.has_permission(
  p_code text,
  p_scope_type text default 'platform',
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
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    where ur.user_id = auth.uid()
      and p.code = p_code
      and ur.revoked_at is null
      and (ur.scope_type = 'platform' or (ur.scope_type = p_scope_type and ur.scope_id = p_scope_id))
  );
$$;

create or replace function private.is_self(p_user_id uuid)
returns boolean
language sql
stable
as $$
  select auth.uid() = p_user_id;
$$;

-- Convenience wrapper used throughout RLS policies (0007) for the common
-- "any admin-console user" check, equivalent to has_permission('applications.view').
create or replace function public.is_admin(uid uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.user_roles ur
    join public.roles r on r.id = ur.role_id
    where ur.user_id = uid
      and ur.revoked_at is null
      and r.code in ('platform_admin', 'program_manager', 'reviewer')
  );
$$;
