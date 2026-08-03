# Bauhaven Database Schema — Reference

Companion to `001_initial_schema.sql`, which has been **tested end-to-end against a real Postgres 16 instance** — it runs clean, all 28 tables and foreign keys resolve. Ready to run as your first Supabase migration.

## Entity list

| Table | Purpose |
|---|---|
| `users` | Core identity — `id` **is** the Supabase Auth user id, auto-populated via trigger on signup; no role field, see `user_roles` |
| `user_roles` | One row per role a person holds, concurrently or over time |
| `permissions` | Role-level default access per module/action |
| `user_permission_overrides` | Individual grants on top of the role default (e.g. one Staff member's Finance access) |
| `announcements` | Platform-wide or role-scoped posts |
| `notifications` | System-generated alerts per user |
| `requests` | Absence/unavailability requests |
| `request_approvals` | One row per required approver (quorum varies by requester role) |
| `invitations` | Onboarding links for new users |
| `issue_reports` | User-submitted problems, routed by category |
| `programs` | Courses and programs (unified type field) |
| `services` | Lightweight catalog, no booking/pricing yet |
| `applications` | Public applications to join a Program |
| `enrollments` | User ↔ Program, with duration/module overrides |
| `projects` / `tasks` | Assignable work, optionally scoped to a Program |
| `submissions` | Work submitted against a Task |
| `feedback` | Comments/ratings on a Submission |
| `attendance_sessions` / `attendance_records` | Append-only attendance, corrections via `corrects_id` |
| `finance_records` | Append-only transactions; separately tracks payer, recorder, and approver — e.g. a Student pays, Staff records, Admin approves |
| `assets` | Physical/digital inventory, assignable to a user |
| `pages` / `content_blocks` | Website content editor tables, feed the live Next.js site |
| `portfolio_entries` | Intern/student work showcased publicly |
| `blogs` | User-authored posts, gated by Admin/Staff approval |
| `testimonies` | Intern/student experience write-ups |

## Relationships summary

- `user_roles.user_id → users.id` (many roles per user)
- `user_roles.program_id → programs.id` (optional scope, e.g. "Mentor for Program X")
- `enrollments`, `applications`, `tasks`, `attendance_sessions` all hang off `programs.id`
- `submissions.task_id → tasks.id`, `feedback.submission_id → submissions.id`
- `attendance_records.session_id → attendance_sessions.id`; corrections reference an earlier `attendance_records.id` via `corrects_id` rather than editing the row
- `finance_records` corrections work the same way via `corrects_id`
- `issue_reports` optionally links to `assets.id` or `programs.id` depending on category
- `request_approvals.request_id → requests.id`, one row per required approver

## `users.id` is the Supabase Auth id

`users` doesn't generate its own id — `id` references `auth.users(id)` directly, so there's exactly one identifier for a person across the whole platform. A trigger (`handle_new_user`) auto-creates the matching `public.users` row the moment someone signs up via Supabase Auth, pulling `name` from signup metadata if provided (falls back to the email prefix if not) — so app code never has to remember to create the profile row manually. Tested locally against a stub `auth.users` table and confirmed both the metadata and no-metadata signup paths populate correctly.

## Finance payment chain

A `finance_records` row separately tracks who **paid** (`payer_id`/`payer_name` — a Student paying their own fee, or an external payer with no account), who **recorded** it (`recorded_by` — typically Staff), and who **approved** it (`approved_by` — Admin). `payer_name` is always stored even when `payer_id` is set, since a denormalized snapshot of the name at transaction time is worth keeping independent of whether the account or its name ever changes later.

## Why append-only for Attendance and Finance

Both are audit-sensitive — you need to know what actually happened, including mistakes and their corrections, not just the current "truth." A correction is a new row with `corrects_id` pointing at the original, never an `UPDATE`. This also sidesteps sync conflicts if attendance is ever taken offline and synced later.

### Reading an append-only table: resolve to the row nothing supersedes

The cost of append-only is on the read side, and it applies to **every** consumer — Admin-web, Admin-native, and Academy alike. A plain `select` over `attendance_records` for a session returns the corrections *and* the rows they corrected, so a student marked Present and then corrected to Absent is counted twice, once in each total. Same for `finance_records`: a corrected transaction sums twice.

The rule is **"the row no other row supersedes"** — the id that appears in no other row's `corrects_id` — resolved per `(session_id, user_id)` for attendance and per correction chain for finance.

It is deliberately *not* "the row with the newest `created_at`". Two rows written in the same statement carry the same timestamp exactly, so ordering by `created_at` alone picks between an original and its correction arbitrarily. `created_at` is a tie-breaker only between rows that are *all* still standing, which is what a genuine concurrent write produces (two people marking the same student, neither insert having seen the other) — there, last-write-wins is the only answer available, and ordering by id after it keeps the result stable across renders.

Writers have the mirror obligation: resolve the row being superseded **at write time, server-side**, from what is actually in the table. A `corrects_id` a client was holding is already stale if someone else wrote in between, and using it forks the chain into two rows that both look current rather than extending it.

Implemented and tested in `bauhaven-admin-web` as `src/lib/attendance-resolve.ts`, shared by the roster, the stat cards, and the write path so there is no second implementation to drift.

## Index list (query → index)

| Query this serves | Index |
|---|---|
| Login lookup by email | `idx_users_email` (unique, excludes soft-deleted) |
| "What are this user's active roles?" | `idx_user_roles_user_status` |
| Permission check by role | `idx_user_roles_role` |
| Unread notifications for a user | `idx_notifications_user_unread` |
| A user's pending/approved requests | `idx_requests_requester_status` |
| Applications for a Program by status | `idx_applications_program_status` |
| Enrollments for a Program | `idx_enrollments_program` |
| "My tasks due soon" | `idx_tasks_assigned_deadline` |
| Submissions for a Task / by a user | `idx_submissions_task`, `idx_submissions_user` |
| Attendance for a session / a user's history | `idx_attendance_session_user`, `idx_attendance_user` |
| Monthly finance analysis | `idx_finance_created_at` |
| Payment history for a specific payer | `idx_finance_payer` |
| Assets by owner / by status | `idx_assets_assigned`, `idx_assets_status` |
| Published pages for the live site | `idx_pages_status` |
| A user's portfolio entries | `idx_portfolio_user_status` |
| Blog moderation queue | `idx_blogs_status` |
| Issue report triage | `idx_issue_reports_status_category` |

## Row-Level Security — implemented and tested

`002_row_level_security.sql` implements the four buckets described earlier, plus helper functions (`auth_is_admin()`, `auth_is_staff()`, `auth_has_permission()`) that check the caller's `user_roles`/`user_permission_overrides`.

**A real bug was caught during testing and fixed:** the helper functions query `user_roles`, which itself has an RLS policy that calls those same functions — infinite recursion. Fixed by making the helpers `SECURITY DEFINER`, so their internal query bypasses RLS rather than re-triggering the policy that called them. Confirmed no recursion after the fix.

**A second bug was caught while building the Admin Applications screen — `003_application_approval_rls.sql`.** `applications_update` was `using (auth_is_admin_or_staff())` with no `WITH CHECK`, so any Staff member could write any status, `'approved'` included — while `Bauhaven-Admin-Feature-Spec.md` §8 has always said final approval is Admin-only. The policy and its own spec disagreed, and the matrix below had no case for it, so nothing caught it. UPDATE policies need **both** clauses to express "who may touch this row" and "what it may become" separately; `USING` alone only answers the first. Approval is now enforced in the database, in the Server Action, and in the UI independently — the UI hiding a button is not authorization, since a Server Action is reachable by direct POST.

**A third gap was caught while building the Admin Tasks screen — `004_submission_grading_rls.sql`.** `submissions` had `SELECT` and `INSERT` policies and no `UPDATE`, so `submissions.grade` — the only column in the schema that can hold a grade — was unwritable by anyone. Features #5 ("Grade student on Program") and #17 ("Feedback on submission") were both Must-haves that could not be implemented as specified. See "`submissions` had the same gap" below. The pattern across all three: the policies were reviewed by reading them, and each mismatch only surfaced when a screen actually tried to use them.

Tested against a live Postgres instance with seeded Admin/Staff/Student accounts, covering all four buckets:

| Check | Result |
|---|---|
| Admin can read/write `finance_records` | ✅ |
| Student has zero access to `finance_records` | ✅ |
| Staff with no override has zero access to `finance_records` | ✅ |
| A Student sees their own assigned Task | ✅ |
| A different Student cannot see that Task at all | ✅ |
| A Student can check in to attendance for a program they're enrolled in | ✅ |
| A Student is blocked from checking in to a session for a program they're **not** enrolled in | ✅ (blocked) |
| Staff can still log attendance for a student regardless of that student's enrollment | ✅ (bypass intact) |
| A Student can submit their own work | ✅ |
| A Student cannot submit work as someone else | ✅ (blocked) |
| Anonymous (`anon` role) can submit an Application | ✅ |
| Anonymous cannot read `finance_records` | ✅ |
| A Student can create their own Testimony | ✅ |
| A Student cannot create a Testimony as someone else | ✅ (blocked) |
| Staff can confirm or decline an Application | ✅ |
| **Staff cannot approve an Application** | ✅ (blocked, as of `003`) |
| Admin can approve an Application | ✅ |
| **Staff can grade a Submission** | ✅ (as of `004` — impossible before it, see below) |
| A Student cannot grade their own Submission | ✅ (blocked) |
| Staff can leave Feedback on a Submission | ✅ |

`finance_records` has no `UPDATE` policy at all — combined with the append-only convention, this means corrections can only happen as new rows with `corrects_id`, enforced at the database level, not just by convention.

### `submissions` had the same gap, and it wasn't deliberate

`002` gave `submissions` a `SELECT` and an `INSERT` policy and no `UPDATE` — but unlike `finance_records`, nothing about `submissions` is append-only, and the omission made a Must-have feature unimplementable. The grade lives on `submissions.grade`; it is the only column in the schema that can hold one (`feedback.rating` is a 1-5 integer, and `tasks` has no grade column), so with no `UPDATE` policy nobody could grade anything. Found while building the Tasks screen, fixed in `004_submission_grading_rls.sql` with an admin/staff-only `submissions_update`.

Deliberately not extended to the submission's owner: a student who could update their own row could rewrite their own grade, and `submissions` has no `corrects_id` chain to make that visible the way `attendance_records` does.

This is the third policy-versus-spec mismatch found by building against the schema rather than reading it (after the RLS recursion bug and `003`'s application-approval gap). Building the feature is what keeps finding them.

## Where a grade lives, and where feedback lives

They are two different rows, and conflating them is the easy mistake:

- **`submissions.grade`** — free text, one per submission. "88%", "A-", "Pass". This is the grade the Admin task list shows on its badge.
- **`feedback.comment`** — `not null` text, and **`feedback.rating`** — a nullable 1-5 integer. A satisfaction-style rating attached to a written comment, *not* the grade. `feedback` has no unique constraint on `submission_id`, so several comments on one submission are the design.

`tasks.status` moving to `'graded'` is the third piece. Nothing in PostgREST commits those three writes together — see `Bauhaven-Admin-Feature-Spec.md` §8, "Tasks", for the ordering that makes a partial failure recoverable, and for the Postgres-function fix that would make it atomic.

## Review checklist (per the data-modeling standard)

- [x] Every table: UUID pk, `created_at` (+ `updated_at` where mutable, + `deleted_at` where soft-deleted)
- [x] No floats for money; `currency` stored alongside `amount_minor`
- [x] Foreign keys named and constrained (deferred FKs added via `alter table` where a forward reference was needed — `user_roles.program_id`, `issue_reports.asset_id`/`program_id`)
- [x] EN/FR fields on every user-visible content table
- [x] Append-only chosen for `finance_records` and `attendance_records`
- [x] Indexes justified by a named query above
- [x] Ownership path exists on every table for future RLS
- [x] RLS policies — implemented in `002_row_level_security.sql`, tested against live sessions, one recursion bug found and fixed
