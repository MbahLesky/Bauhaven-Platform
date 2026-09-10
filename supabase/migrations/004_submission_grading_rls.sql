-- Bauhaven Platform — Staff/Admin can grade a submission
-- Depends on: 002_row_level_security.sql
--
-- Closes a gap between the spec and the shipped policy, found while building the Tasks
-- screen in bauhaven-admin-web.
--
-- The grade lives on `submissions.grade` — it is the only column in the schema that can
-- hold one. `feedback.rating` is a 1-5 integer, which cannot express the "Graded — 88%"
-- the wireframe shows, and `tasks` has no grade column at all.
--
-- But `002` gave `submissions` only a SELECT and an INSERT policy, and the INSERT is
-- `user_id = auth.uid()` — a student inserting their own work. With no UPDATE policy,
-- *nobody* could write `submissions.grade` after the row existed, so feature #5 ("Grade
-- student on Program", Admin + Staff, Must) and feature #17 ("Feedback on submission")
-- were unimplementable as specified: Staff could write the `feedback` row and flip
-- `tasks.status` to 'graded', but the grade itself had nowhere to go.
--
-- This is the same class of bug as `003` — a policy set that doesn't match its own spec
-- — so the matching cases are added to the RLS matrix in Bauhaven-Database-Schema.md
-- rather than left to be rediscovered.

-- Grading is Admin/Staff work, matching `feedback_insert` in 002. Deliberately *not*
-- extended to the submission's owner: a student who could update their own row could
-- rewrite their own grade, and `submissions.grade` has no append-only correction chain
-- to make that visible the way `attendance_records` does.
--
-- USING and WITH CHECK are both admin/staff so a grader can neither reach a row they
-- shouldn't nor hand one off to someone else by rewriting `user_id`.
create policy submissions_update on submissions for update
  using (auth_is_admin_or_staff())
  with check (auth_is_admin_or_staff());
