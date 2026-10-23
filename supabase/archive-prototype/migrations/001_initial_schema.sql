-- Bauhaven Platform — Initial Schema
-- Target: Postgres / Supabase
-- Conventions: UUID pk, created_at/updated_at (timestamptz, UTC), soft delete via deleted_at
--              where history matters, enums as text + CHECK, money as amount_minor + currency,
--              EN/FR bilingual content as _en/_fr column pairs, append-only for finance/attendance.

create extension if not exists pgcrypto; -- for gen_random_uuid()

create table schema_meta (
  version integer primary key,
  applied_at timestamptz not null default now()
);
insert into schema_meta (version) values (1);

create or replace function set_updated_at()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql;

-- =========================================================
-- CORE
-- =========================================================

-- users.id IS the Supabase Auth user id (auth.users.id) — not independently generated.
-- A row is created here automatically on signup via the trigger below.
create table users (
  id uuid primary key references auth.users(id) on delete cascade,
  name text not null,
  email text unique,
  phone text unique,
  location text,
  profile_photo_url text,
  preferred_language text not null default 'en' check (preferred_language in ('en','fr')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger trg_users_updated_at before update on users
  for each row execute function set_updated_at();
create unique index idx_users_email on users (email) where deleted_at is null;

-- Auto-create the public.users row whenever someone signs up via Supabase Auth,
-- so app code never has to remember to do it manually.
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.users (id, name, email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', split_part(new.email, '@', 1)),
    new.email
  );
  return new;
end;
$$ language plpgsql security definer;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- One row per role a person holds; a user can hold several, concurrently or over time.
create table user_roles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  role text not null check (role in ('admin','staff','intern','student','holiday_maker')),
  staff_sub_role text check (staff_sub_role in ('auditor','coordinator','programme_manager','mentor')),
  program_id uuid, -- optional scope; FK added after `programs` exists
  status text not null default 'active' check (status in ('active','inactive')),
  started_at timestamptz not null default now(),
  ended_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_user_roles_updated_at before update on user_roles
  for each row execute function set_updated_at();
create index idx_user_roles_user_status on user_roles (user_id, status);
create index idx_user_roles_role on user_roles (role);

-- Role-level permission defaults (role/module/action -> allowed). App-editable, not code.
create table permissions (
  id uuid primary key default gen_random_uuid(),
  role text not null,
  module text not null,
  action text not null,
  allowed boolean not null default false,
  unique (role, module, action)
);

-- Per-individual overrides on top of the role default (e.g. Finance access for one Staff member,
-- Task-creation for one Student).
create table user_permission_overrides (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  module text not null,
  action text not null,
  granted boolean not null default true,
  granted_by uuid not null references users(id),
  created_at timestamptz not null default now(),
  unique (user_id, module, action)
);

create table announcements (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references users(id),
  title_en text not null,
  title_fr text,
  body_en text not null,
  body_fr text,
  scope_role text, -- null = platform-wide
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_announcements_updated_at before update on announcements
  for each row execute function set_updated_at();

create table notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  type text not null,
  payload jsonb not null default '{}',
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index idx_notifications_user_unread on notifications (user_id) where read_at is null;

-- Absence / unavailability requests. Approval quorum varies by requester role
-- (User -> 1 Staff, Staff -> 1 Admin, Admin -> every other Admin), so approvals
-- live in their own table rather than a single approver_id column.
create table requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references users(id),
  type text not null default 'absence',
  start_date date not null,
  end_date date not null,
  reason text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_requests_updated_at before update on requests
  for each row execute function set_updated_at();
create index idx_requests_requester_status on requests (requester_id, status);

create table request_approvals (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references requests(id) on delete cascade,
  approver_id uuid not null references users(id),
  decision text check (decision in ('approved','rejected')),
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  unique (request_id, approver_id)
);

create table invitations (
  id uuid primary key default gen_random_uuid(),
  email text not null,
  invited_role text not null,
  invited_by uuid not null references users(id),
  token text not null unique,
  accepted_at timestamptz,
  expires_at timestamptz not null,
  created_at timestamptz not null default now()
);

create table issue_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references users(id),
  category text not null default 'general',
  description text not null,
  status text not null default 'open' check (status in ('open','in_progress','resolved')),
  asset_id uuid,   -- FK added after `assets` exists
  program_id uuid, -- FK added after `programs` exists
  resolved_by uuid references users(id),
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_issue_reports_updated_at before update on issue_reports
  for each row execute function set_updated_at();
create index idx_issue_reports_status_category on issue_reports (status, category);

-- =========================================================
-- ADMIN — Courses/Programs, Services, Applications, Enrollment
-- =========================================================

create table programs (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('course','program')),
  title_en text not null,
  title_fr text,
  description_en text,
  description_fr text,
  duration_days integer,
  fee_amount_minor integer, -- whole francs for XAF; minor units for other currencies
  fee_currency text default 'XAF',
  module_count integer,
  status text not null default 'active' check (status in ('active','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger trg_programs_updated_at before update on programs
  for each row execute function set_updated_at();

alter table user_roles add constraint fk_user_roles_program
  foreign key (program_id) references programs(id);
alter table issue_reports add constraint fk_issue_reports_program
  foreign key (program_id) references programs(id);

create table services (
  id uuid primary key default gen_random_uuid(),
  name_en text not null,
  name_fr text,
  description_en text,
  description_fr text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_services_updated_at before update on services
  for each row execute function set_updated_at();

create table applications (
  id uuid primary key default gen_random_uuid(),
  applicant_name text not null,
  applicant_email text not null,
  applicant_phone text,
  program_id uuid not null references programs(id),
  status text not null default 'submitted'
    check (status in ('submitted','confirmed','approved','declined')),
  reviewed_by uuid references users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_applications_updated_at before update on applications
  for each row execute function set_updated_at();
create index idx_applications_program_status on applications (program_id, status);

create table enrollments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  program_id uuid not null references programs(id),
  status text not null default 'active' check (status in ('active','completed','withdrawn')),
  start_date date,
  end_date date,
  duration_override_days integer,
  module_count_override integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, program_id)
);
create trigger trg_enrollments_updated_at before update on enrollments
  for each row execute function set_updated_at();
create index idx_enrollments_program on enrollments (program_id);

-- =========================================================
-- ADMIN — Tasks, Projects, Submissions, Feedback
-- =========================================================

create table projects (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  program_id uuid references programs(id),
  created_by uuid not null references users(id),
  status text not null default 'active' check (status in ('active','approved','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_projects_updated_at before update on projects
  for each row execute function set_updated_at();

create table tasks (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references projects(id),
  program_id uuid references programs(id),
  title text not null,
  description text,
  assigned_to uuid references users(id),
  created_by uuid not null references users(id),
  deadline timestamptz,
  status text not null default 'open' check (status in ('open','submitted','graded','archived')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_tasks_updated_at before update on tasks
  for each row execute function set_updated_at();
create index idx_tasks_assigned_deadline on tasks (assigned_to, deadline);

create table submissions (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references tasks(id),
  user_id uuid not null references users(id),
  content_url text,
  submitted_at timestamptz not null default now(),
  grade text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_submissions_updated_at before update on submissions
  for each row execute function set_updated_at();
create index idx_submissions_task on submissions (task_id);
create index idx_submissions_user on submissions (user_id);

create table feedback (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references submissions(id),
  author_id uuid not null references users(id),
  comment text not null,
  rating integer check (rating between 1 and 5),
  created_at timestamptz not null default now()
);

-- =========================================================
-- ADMIN — Attendance (append-only: corrections are new rows)
-- =========================================================

create table attendance_sessions (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references programs(id),
  session_date date not null,
  created_by uuid not null references users(id),
  created_at timestamptz not null default now()
);

create table attendance_records (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references attendance_sessions(id),
  user_id uuid not null references users(id),
  status text not null check (status in ('present','absent','excused')),
  checked_in_at timestamptz,
  corrects_id uuid references attendance_records(id), -- points to the row this corrects, if any
  created_at timestamptz not null default now()
);
create index idx_attendance_session_user on attendance_records (session_id, user_id);
create index idx_attendance_user on attendance_records (user_id);

-- =========================================================
-- ADMIN — Finance (append-only: corrections are new rows)
-- =========================================================

-- Payment workflow: a payer (e.g. a Student paying their fee) is recorded by Staff
-- and approved by Admin — three distinct people can be on one row.
create table finance_records (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('income','expense')),
  description text not null,
  amount_minor integer not null,
  currency text not null default 'XAF',
  receipt_ref text,
  payer_id uuid references users(id), -- nullable: payer may not hold a Bauhaven account
  payer_name text,                    -- always captured, even if payer_id is null
  recorded_by uuid not null references users(id),
  approved_by uuid references users(id),
  approved_at timestamptz,
  status text not null default 'pending' check (status in ('pending','approved')),
  corrects_id uuid references finance_records(id),
  created_at timestamptz not null default now()
);
create index idx_finance_created_at on finance_records (created_at);
create index idx_finance_status on finance_records (status);
create index idx_finance_payer on finance_records (payer_id);

-- =========================================================
-- ADMIN — Assets
-- =========================================================

create table assets (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text not null check (type in ('physical','digital')),
  status text not null default 'fine' check (status in ('fine','needs_repair','retired')),
  assigned_to uuid references users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);
create trigger trg_assets_updated_at before update on assets
  for each row execute function set_updated_at();
create index idx_assets_assigned on assets (assigned_to);
create index idx_assets_status on assets (status);

alter table issue_reports add constraint fk_issue_reports_asset
  foreign key (asset_id) references assets(id);

-- =========================================================
-- ADMIN — Content editor (feeds the live Next.js site)
-- =========================================================

create table pages (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title_en text not null,
  title_fr text,
  body_en text,
  body_fr text,
  status text not null default 'draft' check (status in ('draft','published')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_pages_updated_at before update on pages
  for each row execute function set_updated_at();
create index idx_pages_status on pages (status);

create table content_blocks (
  id uuid primary key default gen_random_uuid(),
  page_id uuid references pages(id),
  key text not null,
  title_en text,
  title_fr text,
  body_en text,
  body_fr text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_content_blocks_updated_at before update on content_blocks
  for each row execute function set_updated_at();

create table portfolio_entries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  program_id uuid references programs(id),
  title_en text not null,
  title_fr text,
  description_en text,
  description_fr text,
  media_url text,
  status text not null default 'draft' check (status in ('draft','published')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_portfolio_entries_updated_at before update on portfolio_entries
  for each row execute function set_updated_at();
create index idx_portfolio_user_status on portfolio_entries (user_id, status);

create table blogs (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null references users(id),
  title_en text not null,
  title_fr text,
  body_en text not null,
  body_fr text,
  status text not null default 'draft' check (status in ('draft','pending','approved')),
  approved_by uuid references users(id),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_blogs_updated_at before update on blogs
  for each row execute function set_updated_at();
create index idx_blogs_status on blogs (status);

-- =========================================================
-- ACADEMY — Testimonies
-- =========================================================

create table testimonies (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id),
  program_id uuid references programs(id),
  content_en text not null,
  content_fr text,
  status text not null default 'submitted' check (status in ('submitted','published')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create trigger trg_testimonies_updated_at before update on testimonies
  for each row execute function set_updated_at();
