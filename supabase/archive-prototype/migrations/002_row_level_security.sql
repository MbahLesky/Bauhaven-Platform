-- Bauhaven Platform — Row-Level Security
-- Depends on: 001_initial_schema.sql
-- Approach: helper functions read the caller's identity/roles from auth.uid() and
--           user_roles, then every table gets policies from one of four buckets:
--           ownership, scoped, public-read, or admin-only.

-- =========================================================
-- HELPER FUNCTIONS
-- =========================================================

-- SECURITY DEFINER is required here: these functions query user_roles, which itself
-- has RLS policies that call these same functions. Without SECURITY DEFINER, that's
-- infinite recursion (each check re-triggers the policy it's being called from).
-- Running as the function owner (bypassing RLS internally) breaks the cycle.

create or replace function auth_has_role(target_role text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from user_roles
    where user_id = auth.uid()
      and role = target_role
      and status = 'active'
  );
$$;

create or replace function auth_is_admin()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select auth_has_role('admin');
$$;

create or replace function auth_is_staff()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select auth_has_role('staff');
$$;

create or replace function auth_is_admin_or_staff()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select auth_is_admin() or auth_is_staff();
$$;

-- Individual override takes precedence over the role-level default.
create or replace function auth_has_permission(p_module text, p_action text)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce(
    (select granted from user_permission_overrides
     where user_id = auth.uid() and module = p_module and action = p_action),
    (select bool_or(p.allowed) from permissions p
     join user_roles ur on ur.role = p.role
     where ur.user_id = auth.uid() and ur.status = 'active'
       and p.module = p_module and p.action = p_action),
    false
  );
$$;

-- =========================================================
-- CORE
-- =========================================================

alter table users enable row level security;
create policy users_select_own on users for select
  using (id = auth.uid() or auth_is_admin_or_staff());
create policy users_update_own on users for update
  using (id = auth.uid() or auth_is_admin());

alter table user_roles enable row level security;
create policy user_roles_select on user_roles for select
  using (user_id = auth.uid() or auth_is_admin_or_staff());
create policy user_roles_write on user_roles for all
  using (auth_is_admin())
  with check (auth_is_admin());

alter table permissions enable row level security;
create policy permissions_admin_only on permissions for all
  using (auth_is_admin()) with check (auth_is_admin());

alter table user_permission_overrides enable row level security;
create policy overrides_admin_only on user_permission_overrides for all
  using (auth_is_admin()) with check (auth_is_admin());

alter table announcements enable row level security;
create policy announcements_select on announcements for select
  using (published_at is not null or auth_is_admin_or_staff());
create policy announcements_write on announcements for insert
  with check (auth_is_admin_or_staff());
create policy announcements_update on announcements for update
  using (auth_is_admin_or_staff());

alter table notifications enable row level security;
create policy notifications_own on notifications for select
  using (user_id = auth.uid());
create policy notifications_update_own on notifications for update
  using (user_id = auth.uid());

alter table requests enable row level security;
create policy requests_select on requests for select
  using (requester_id = auth.uid() or auth_is_admin_or_staff());
create policy requests_insert on requests for insert
  with check (requester_id = auth.uid());

alter table request_approvals enable row level security;
create policy request_approvals_select on request_approvals for select
  using (approver_id = auth.uid()
    or exists (select 1 from requests r where r.id = request_id and r.requester_id = auth.uid())
    or auth_is_admin());
create policy request_approvals_write on request_approvals for update
  using (approver_id = auth.uid());

alter table invitations enable row level security;
create policy invitations_admin_staff on invitations for all
  using (auth_is_admin_or_staff()) with check (auth_is_admin_or_staff());

alter table issue_reports enable row level security;
create policy issue_reports_select on issue_reports for select
  using (reporter_id = auth.uid() or auth_is_admin_or_staff());
create policy issue_reports_insert on issue_reports for insert
  with check (reporter_id = auth.uid());
create policy issue_reports_update on issue_reports for update
  using (auth_is_admin_or_staff());

-- =========================================================
-- ADMIN — Courses/Programs, Services, Applications, Enrollment
-- =========================================================

alter table programs enable row level security;
create policy programs_select_all on programs for select using (true); -- catalog is visible to all logged-in users
create policy programs_write on programs for insert with check (auth_is_admin_or_staff());
create policy programs_update on programs for update using (auth_is_admin_or_staff());
create policy programs_delete on programs for delete using (auth_is_admin());

alter table services enable row level security;
create policy services_select_all on services for select using (true);
create policy services_write on services for all
  using (auth_is_admin_or_staff()) with check (auth_is_admin_or_staff());

alter table applications enable row level security;
create policy applications_insert_public on applications for insert with check (true); -- public submission
create policy applications_select on applications for select using (auth_is_admin_or_staff());
create policy applications_update on applications for update using (auth_is_admin_or_staff());

alter table enrollments enable row level security;
create policy enrollments_select on enrollments for select
  using (user_id = auth.uid() or auth_is_admin_or_staff());
create policy enrollments_write on enrollments for all
  using (auth_is_admin()) with check (auth_is_admin());

-- =========================================================
-- ADMIN — Tasks, Projects, Submissions, Feedback
-- =========================================================

alter table projects enable row level security;
create policy projects_select on projects for select
  using (created_by = auth.uid() or auth_is_admin_or_staff());
create policy projects_insert on projects for insert
  with check (auth_is_admin_or_staff() or auth_has_permission('tasks','create'));
create policy projects_update on projects for update using (auth_is_admin_or_staff());

alter table tasks enable row level security;
create policy tasks_select on tasks for select
  using (assigned_to = auth.uid() or created_by = auth.uid() or auth_is_admin_or_staff());
create policy tasks_insert on tasks for insert
  with check (auth_is_admin_or_staff() or auth_has_permission('tasks','create'));
create policy tasks_update on tasks for update
  using (created_by = auth.uid() or auth_is_admin_or_staff());
create policy tasks_delete on tasks for delete using (created_by = auth.uid());

alter table submissions enable row level security;
create policy submissions_select on submissions for select
  using (user_id = auth.uid() or auth_is_admin_or_staff());
create policy submissions_insert on submissions for insert with check (user_id = auth.uid());

alter table feedback enable row level security;
create policy feedback_select on feedback for select
  using (auth_is_admin_or_staff()
    or exists (select 1 from submissions s where s.id = submission_id and s.user_id = auth.uid()));
create policy feedback_insert on feedback for insert with check (auth_is_admin_or_staff());

-- =========================================================
-- ADMIN — Attendance (append-only)
-- =========================================================

alter table attendance_sessions enable row level security;
create policy attendance_sessions_select on attendance_sessions for select using (true);
create policy attendance_sessions_write on attendance_sessions for insert
  with check (auth_is_admin_or_staff());

-- A student self-checking in must be actively enrolled in the session's program.
-- Staff/Admin recording on someone else's behalf bypass this (they're not "checking in" themselves).
create or replace function auth_enrolled_in_session_program(p_session_id uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from attendance_sessions s
    join enrollments e on e.program_id = s.program_id
    where s.id = p_session_id
      and e.user_id = auth.uid()
      and e.status = 'active'
  );
$$;

alter table attendance_records enable row level security;
create policy attendance_records_select on attendance_records for select
  using (user_id = auth.uid() or auth_is_admin_or_staff());
create policy attendance_records_insert on attendance_records for insert
  with check (
    (user_id = auth.uid() and auth_enrolled_in_session_program(session_id)) -- self check-in: must be enrolled
    or auth_is_admin_or_staff() -- Staff/Admin logging on someone's behalf: no enrollment check needed
  );

-- =========================================================
-- ADMIN — Finance (admin/staff-with-access only, append-only)
-- =========================================================

alter table finance_records enable row level security;
create policy finance_select on finance_records for select
  using (auth_is_admin() or auth_has_permission('finance','view'));
create policy finance_insert on finance_records for insert
  with check (auth_is_admin() or auth_has_permission('finance','create'));
-- No update policy at all: append-only means corrections are new rows (corrects_id),
-- never edits — omitting UPDATE entirely enforces that at the database level.

-- =========================================================
-- ADMIN — Assets
-- =========================================================

alter table assets enable row level security;
create policy assets_select on assets for select
  using (assigned_to = auth.uid() or auth_is_admin_or_staff());
create policy assets_write on assets for all
  using (auth_is_admin_or_staff()) with check (auth_is_admin_or_staff());

-- =========================================================
-- ADMIN — Content editor (public-read once published)
-- =========================================================

alter table pages enable row level security;
create policy pages_public_read on pages for select using (status = 'published');
create policy pages_staff_read on pages for select using (auth_is_admin_or_staff());
create policy pages_write on pages for all
  using (auth_is_admin_or_staff()) with check (auth_is_admin_or_staff());

alter table content_blocks enable row level security;
create policy content_blocks_read on content_blocks for select using (true);
create policy content_blocks_write on content_blocks for all
  using (auth_is_admin_or_staff()) with check (auth_is_admin_or_staff());

alter table portfolio_entries enable row level security;
create policy portfolio_public_read on portfolio_entries for select using (status = 'published');
create policy portfolio_own_read on portfolio_entries for select using (user_id = auth.uid());
create policy portfolio_write on portfolio_entries for all
  using (auth_is_admin_or_staff()) with check (auth_is_admin_or_staff());

alter table blogs enable row level security;
create policy blogs_public_read on blogs for select using (status = 'approved');
create policy blogs_own_read on blogs for select using (author_id = auth.uid());
create policy blogs_staff_read on blogs for select using (auth_is_admin_or_staff());
create policy blogs_insert on blogs for insert with check (author_id = auth.uid());
create policy blogs_approve on blogs for update using (auth_is_admin_or_staff());

-- =========================================================
-- ACADEMY — Testimonies
-- =========================================================

alter table testimonies enable row level security;
create policy testimonies_select on testimonies for select
  using (user_id = auth.uid() or status = 'published' or auth_is_admin_or_staff());
create policy testimonies_insert on testimonies for insert with check (user_id = auth.uid());
