-- Bauhaven Platform — Application approval is Admin-only
-- Depends on: 002_row_level_security.sql
--
-- Closes a gap between the spec and the shipped policy. Bauhaven-Admin-Feature-Spec.md
-- §8 confirms "Approving an Application is Admin-only (Staff can confirm/decline but
-- not give final approval)", but `applications_update` as written in 002 allowed any
-- admin *or staff* caller to write any status, 'approved' included. Nothing in the
-- database stopped a Staff member from granting final approval — only the UI did, and
-- a Server Action or a direct PostgREST call with a valid Staff session bypasses the
-- UI entirely.
--
-- This is the second instance of the class of bug already recorded in
-- Bauhaven-Database-Schema.md ("an RLS policy that didn't match its own spec"), so the
-- matching test case has been added to that document's RLS matrix rather than left to
-- be rediscovered.

drop policy if exists applications_update on applications;

-- USING decides which rows a caller may update at all; WITH CHECK decides what the row
-- is allowed to look like afterwards. Splitting them is what lets Staff move an
-- application to 'confirmed' or 'declined' while reserving 'approved' for Admin.
--
-- The WITH CHECK reads against the NEW row, so `status <> 'approved'` means "Staff may
-- leave an application in any state except approved" — which also makes an approved
-- application terminal for Staff, since any update they attempt would have to leave
-- the status as 'approved' and fail the check.
create policy applications_update on applications for update
  using (auth_is_admin_or_staff())
  with check (
    auth_is_admin()
    or status <> 'approved'
  );
