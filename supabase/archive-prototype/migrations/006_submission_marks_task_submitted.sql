-- Bauhaven Platform — submitting work moves its task to 'submitted'
-- Depends on: 001_initial_schema.sql, 002_row_level_security.sql
--
-- Found while building Academy-web's Tasks feature, which is the other half of
-- Admin-web's. The two apps had incompatible assumptions about who performs the
-- open → submitted transition, and the answer was "nobody":
--
--   * Admin-web **creates** tasks with `status = 'open'` and **grades** them with
--     `.eq('status','submitted')` as a concurrency guard. It reads the submitted state
--     and never writes it — reasonably, since staff don't submit student work.
--   * Academy-web inserts the `submissions` row. `submissions_insert` is
--     `user_id = auth.uid()`, so a student can do that.
--   * `tasks_update` is `created_by = auth.uid() or auth_is_admin_or_staff()`. A student
--     **assigned** a task has `assigned_to = auth.uid()` but `created_by = <staff>`, so
--     they cannot update it at all.
--   * No trigger did it either. The only triggers on `tasks` and `submissions` maintain
--     `updated_at`.
--
-- Net effect before this migration: a student could submit work, and the task stayed
-- 'open' forever. Admin's "Submitted" queue would be permanently empty, and grading
-- would be impossible — `gradeSubmission`'s `.eq('status','submitted')` matches zero
-- rows, which the UI reports as "already graded by someone else". Silent on both sides.
--
-- =========================================================================
-- Why a trigger rather than widening tasks_update
-- =========================================================================
--
-- Letting the assignee update their own task would work, but it grants far more than the
-- problem needs: `title`, `deadline`, `description` and `assigned_to` would all become
-- student-writable, and a student could reassign or un-deadline their own work. Column
-- privileges could narrow that (as `005` does for finance), but it would still leave the
-- transition as something every client has to remember to perform — Academy-web today,
-- Academy-native at M5, and anything else later. One of them would eventually forget,
-- and the failure is invisible from both ends.
--
-- The invariant belongs to the schema: **a submission exists ⇒ its task is no longer
-- open.** Expressing it here makes it true regardless of which client wrote the row, and
-- means no client needs update rights on `tasks` at all.

create or replace function mark_task_submitted()
returns trigger language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- Only 'open' advances. Deliberately narrow:
  --   * already 'submitted' — a duplicate or replacement submission changes nothing,
  --     which makes this idempotent rather than a no-op that looks like a failure.
  --   * already 'graded' — a resubmission must NOT quietly un-grade finished work and
  --     drop it back into staff's queue with its grade still attached. Whether a
  --     re-submission should reopen grading is a real workflow question nobody has
  --     answered; this migration declines to answer it by accident.
  --   * 'archived' — retired work stays retired.
  update tasks
  set status = 'submitted'
  where id = new.task_id
    and status = 'open';

  return new;
end;
$$;

-- AFTER INSERT: the submission is already durable, so a task that fails to advance can
-- never take the student's work down with it.
create trigger trg_submission_marks_task_submitted
  after insert on submissions
  for each row execute function mark_task_submitted();

-- `security definer` is what makes this work for the student who owns the submission:
-- the function updates `tasks` with the definer's rights, so the assignee never needs a
-- policy permitting them to write the row themselves. It touches exactly one column of
-- exactly one row, addressed by the new submission's own `task_id`, so it cannot be
-- steered into modifying anything else.
