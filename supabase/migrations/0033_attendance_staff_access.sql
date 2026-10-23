-- =============================================================================
-- 0033_attendance_staff_access.sql (also referenced as proposed/03)
-- =============================================================================
-- Grants Bauhaven staff who hold `attendance.record` / `attendance.correct`
-- (Super Admin, Organisation Admin, Programme Manager, Internship Coordinator,
-- Mentor / Supervisor) scoped access to create sessions and record/correct
-- attendance on `public.attendance_sessions` and `public.attendance_records`.
--
-- Cross-table scope checks run inside SECURITY DEFINER helpers so policies never
-- recurse into each other, and both `authenticated` and `anon` receive EXECUTE
-- grants so anonymous requests evaluate to `false` rather than raising 42501.
-- =============================================================================

create or replace function private.has_cohort_attendance_permission(
  p_code text,
  p_cohort_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select
    private.has_permission(p_code, 'cohort', p_cohort_id)
    or exists (
      select 1
      from public.cohorts c
      where c.id = p_cohort_id
        and private.has_permission(p_code, 'offering', c.offering_id)
    );
$$;

create or replace function private.has_session_attendance_permission(
  p_code text,
  p_session_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.attendance_sessions s
    where s.id = p_session_id
      and private.has_cohort_attendance_permission(p_code, s.cohort_id)
  );
$$;

revoke execute on function private.has_cohort_attendance_permission(text, uuid) from public;
revoke execute on function private.has_session_attendance_permission(text, uuid) from public;
grant execute on function private.has_cohort_attendance_permission(text, uuid) to authenticated, anon;
grant execute on function private.has_session_attendance_permission(text, uuid) to authenticated, anon;

-- attendance_sessions ---------------------------------------------------------

drop policy if exists attendance_sessions_select_staff on public.attendance_sessions;
create policy attendance_sessions_select_staff on public.attendance_sessions
  for select
  using (
    public.is_admin(auth.uid())
    or private.has_cohort_attendance_permission('attendance.record', cohort_id)
    or private.has_cohort_attendance_permission('attendance.correct', cohort_id)
  );

drop policy if exists attendance_sessions_insert_staff on public.attendance_sessions;
create policy attendance_sessions_insert_staff on public.attendance_sessions
  for insert
  with check (
    private.has_cohort_attendance_permission('attendance.record', cohort_id)
  );

drop policy if exists attendance_sessions_update_staff on public.attendance_sessions;
create policy attendance_sessions_update_staff on public.attendance_sessions
  for update
  using (
    private.has_cohort_attendance_permission('attendance.record', cohort_id)
  )
  with check (
    private.has_cohort_attendance_permission('attendance.record', cohort_id)
  );

-- attendance_records ----------------------------------------------------------

drop policy if exists attendance_records_select_staff on public.attendance_records;
create policy attendance_records_select_staff on public.attendance_records
  for select
  using (
    public.is_admin(auth.uid())
    or private.has_session_attendance_permission('attendance.record', attendance_session_id)
    or private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  );

drop policy if exists attendance_records_insert_staff on public.attendance_records;
create policy attendance_records_insert_staff on public.attendance_records
  for insert
  with check (
    private.has_session_attendance_permission('attendance.record', attendance_session_id)
    or private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  );

drop policy if exists attendance_records_update_staff on public.attendance_records;
create policy attendance_records_update_staff on public.attendance_records
  for update
  using (
    private.has_session_attendance_permission('attendance.record', attendance_session_id)
    or private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  )
  with check (
    private.has_session_attendance_permission('attendance.record', attendance_session_id)
    or private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  );

