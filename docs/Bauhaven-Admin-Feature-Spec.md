# Bauhaven Admin — Feature Specification

## 1. Problem & background

Admin is the consolidated internal back-office — what would otherwise have been three separate apps (course/program management, finance, assets) plus tasks, attendance, feedback, and the new website content editor, all in one place. Used by Admin (Founders) and Staff (Auditor, Internship Coordinator, Programme Manager, Mentor/Supervisor). Permission scoping matters heavily here: Staff should only see the users/programs they're assigned to, not the whole organization.

## 2. Users

- **Admin (Founders):** full control across every module.
- **Staff:** Auditor, Internship Coordinator, Programme Manager, Mentor/Supervisor share one broad Staff permission set — sub-role is a job title, **not a hard restriction**. Any Staff member can be individually granted extra access on top of that (e.g. Finance access for a specific Auditor) by an Admin.

## 3. User stories

**Courses/Programs**
- As Admin/Staff, I want to create and manage Programs (course or program type) so offerings stay current.
- As Admin, I want to delete a Program — Staff cannot.
- As Admin/Staff, I want to assign or block a Program from specific users so access matches enrollment status.
- As Admin/Staff, I want to set a duration and module count per user (manually, or based on package paid).
- As Admin/Staff, I want to grade a student on a course/program.

**Services**
- As Admin/Staff, I want to add and manage Services (offerings beyond courses/programs) so Bauhaven's full catalog lives in one place.

**Applications & Enrollment**
- As anyone (via Site), I want to submit an Application to join a course/program.
- As Admin/Staff, I want to confirm an Application (first-pass review).
- As Admin, I want to approve an Application (final decision).
- As Admin/Staff, I want to decline an Application.
- As Admin, I want to manage Enrollment; Staff can track it but not directly manage it.

**Tasks & Projects**
- As Admin/Staff, I want to create and manage Projects/Tasks with deadlines and assign them to users. *(Tasks built; **Projects not built** — `projects` is a separate approvable entity, see §8, "Tasks".)*
- As a Student **with permission granted**, I want to create my own Task/Project to track independent work, not just assigned work.
- As Admin, I want to approve a Project.
- As the creator of a Task (Admin/Staff/Student), I want to delete it.
- As Admin/Staff, I want to give Feedback on a submission, scoped to students assigned to me.

**Attendance**
- As Admin/Staff, I want to create attendance sessions and track who attended. *(An approved absence Request from Core auto-marks the session excused — **not built yet**, see §8, "Attendance".)*

**Finance**
- As Admin, I want to grant Finance access to a specific Staff member (typically an Auditor) so they can work with transactions — access isn't automatic just from holding that job title.
- As Admin/Staff (with Finance access), I want to create a Finance Record (log a transaction).
- As Admin, I want to approve/confirm a Finance Record before it's final. *(One Admin, not a quorum — see §8, "Finance".)*
- As Admin, I want to manage and view all Finance Records.
- As Admin, I want to see financial analysis (a computed summary, not a stored table) to gauge Bauhaven's monthly health. *(**Phase 2** — the built screen has two stat cards, not charts.)*

**Assets**
- As Admin/Staff, I want to create/manage an Asset (physical or digital) and track its status. *(Retiring an asset is a status change, not a removal — see §8, "Assets".)*
- As Admin/Staff, I want to assign an Asset to a specific user.

**Website content editor**
- As Admin/Staff, I want to edit Page/ContentBlock content (EN/FR) so the public site stays current without a developer. *(Pages shipped; publishing requires both languages — see §8, "Content Editor".)*
- As Admin/Staff/User, I want to add a Blog post — only Admin/Staff can approve it before it's public.
- As Admin/Staff, I want to publish a PortfolioEntry showcasing an intern/student's work, linked to their profile and Program. *(No consent step — deliberately deferred, see the Project Brief's "Known open items".)*

**Issue reports** *(entity owned by Core, actioned here)*
- As Admin/Staff, I want to view and resolve IssueReports routed to my scope.

## 4. Feature list

| # | Feature | User(s) | Priority | Notes |
|---|---|---|---|---|
| 1 | Create/manage Program (course or program type) | Admin, Staff | Must | |
| 2 | Delete Program | Admin only | Must | RLS policy `programs_delete` exists and stays. **No delete UI in Admin-web v1** — retiring a program is an archive (see §8) |
| 3 | Assign/block Program access per user | Admin, Staff | Must | Ties to scoped `UserRole` access model |
| 4 | Set duration/module count per user (manual or auto by package) | Admin, Staff | Should | Auto-by-package needs a defined pricing model first |
| 5 | Grade student on Program | Admin, Staff | Must | Grade lives on `submissions.grade` (free text), written from the Tasks screen. Needed `004` — `submissions` had no UPDATE policy, see §8 |
| 6 | Add/manage Services (catalog) | Admin, Staff | Should | Light scope for v1 — name/description only |
| 7 | Submit Application (public entry point) | Public via Site | Must | Writes into Admin |
| 8 | Confirm Application | Admin, Staff | Must | |
| 9 | Approve Application | Admin only | Must | |
| 10 | Decline Application | Admin, Staff | Must | |
| 11 | Manage Enrollment | Admin only | Must | |
| 12 | Track Enrollment (read-only) | Staff | Must | |
| 13 | Create/manage Task & Project, assign with deadlines | Admin, Staff, Student (if granted) | Must | Student creation is permission-gated per person, not open to all students. **Tasks shipped; Projects not built** — see §8, "Tasks" |
| 14 | Approve Project | Admin only | Should | **Not built.** `projects` exists with an `approved` status; nothing in Admin-web creates or approves one |
| 15 | Delete Task/Project | Creator | Must | **Not built.** `tasks_delete` RLS (`created_by = auth.uid()`) exists; no delete UI in this pass |
| 16 | Submission | Admin, Staff, Student | Must | |
| 17 | Feedback on submission | Admin, Staff (scoped) | Must | `feedback.comment` + optional 1-5 `feedback.rating`; written together with the grade, see §8 |
| 18 | Attendance sessions: create & track | Admin, Staff | Must | Auto-excuse via approved Request (Core) — **not built**, blocked on Requests; manual marking shipped, see §8 |
| 19 | Grant Finance access to a specific Staff member | Admin only | Must | Access is individually granted, not automatic by sub-role |
| 20 | Finance Record: create | Admin, Staff (with Finance access) | Must | Always inserted `pending`; status is never taken from the caller. Corrections are new rows via `corrects_id` |
| 21 | Finance Record: approve/confirm | Admin only | Must | **A single Admin, not a quorum** — one `approved_by` column. No reject: a wrong entry is corrected, not refused. Needed `005` — no UPDATE policy existed, see §8 |
| 22 | Finance Record: manage & view all | Admin only | Must | Also Staff with an individual `finance:view` grant. The nav link is hidden entirely without it, see §8 |
| 23 | Financial analysis (computed summary) | Admin | Should | **Phase 2.** The Finance screen ships two stat cards (pending count, month-to-date income) and no charts — see `Bauhaven-Development-Plan.md` |
| 24 | Asset: create/manage, set status | Admin, Staff | Must | Flat Admin/Staff gate — no individual override exists, unlike Tasks. **"Retired" is a status, not a delete**, see §8 |
| 25 | Asset: assign to user | Admin, Staff | Must | Any account may hold an asset; `assigned_to` has no role constraint. No delete UI shipped, see §8 |
| 26 | Content editor: Page/ContentBlock (EN/FR) | Admin, Staff | Must | Publish triggers Next.js revalidation. **Pages shipped; `content_blocks` not edited** — a block has no status and goes live with its page. Publish requires both languages, see §8 |
| 27 | Blog: add post | Admin, Staff, User | Should | **Phase 2**, not built — shares the Content Editor's nav section but is out of M2 scope |
| 28 | Blog: approve post | Admin, Staff | Should | **Phase 2**, not built |
| 29 | PortfolioEntry: publish, linked to User + Program | Admin, Staff | Should | Create/edit/publish shipped. **No consent field** — deferred per the Project Brief; curation is the only gate. Revalidates the index only until `slug` exists, see §8 |
| 30 | Resolve IssueReport (routed by category) | Admin, Staff (scoped) | Must | Actioned here, entity owned by Core |

## 5. Out of scope — v1

- Payment/booking flow for Services (catalog only).
- Automatic package-based duration/module assignment (manual entry is enough until packages are formally defined).
- Public-facing Service browsing/purchase (Site can display info; buying is future).

## 6. Success criteria

- Every module (Courses, Applications, Tasks, Attendance, Finance, Assets, Content) is usable by Admin end-to-end without touching the old apps.
- Staff only ever see data scoped to their assignment — verified via a permission audit with zero cross-scope leaks in testing.
- An Application can go from public submission to enrolled Student without manual database work.
  **Not met as of the Enrollment build.** Approving an Application sets its status; it cannot
  create an Enrollment, because `enrollments.user_id` requires a `users` row and an applicant
  has no account until they sign up. The missing link is the invitation/signup step — the
  `invitations` table exists, nothing is built on it. See §8, "Enrollment".

## 7. Constraints, risks & open questions

*(none outstanding — all resolved below)*

## 8. Confirmed decisions

- **Platform: both web and native.** Admin ships as a Next.js web app (primary desk-based back-office use) and a Flutter native app (finance/attendance approvals, asset checks in the field), both against the same Supabase backend and RLS rules. Doubles Admin's frontend build — accepted deliberately.

- Students **cannot** create Assets — the source doc's mention of "student" as an Asset creator wasn't intentional; Asset creation stays Admin/Staff only.

- Sub-roles (Auditor, Coordinator, Programme Manager, Mentor/Supervisor) are **not hard restrictions** — all Staff share one broad permission set; sub-role is a job title, not a wall.
- **Services** stays a simple catalog (name/description) — no pricing or booking in scope.
- **Auditor Finance access is Admin-granted per person**, not automatic from holding the Auditor title — see feature #19.
- **A Student can only create their own Task/Project if an Admin/Staff member has granted that specific permission** — not open to all students by default.
- Approving an Application is Admin-only (Staff can confirm/decline but not give final approval).
- Blog posts written by Users still require Admin/Staff approval before going live — a deliberate moderation gate, not an oversight.

### Enrollment — decisions made while building the screen

- **Enrollment creation is a standalone "+ New enrollment" on the Enrollment screen, not
  an action on an approved Application.** This is forced by the schema, not preference:
  `enrollments.user_id` is `not null references users(id)`, and `users.id` *is* the
  Supabase Auth user id — a `users` row only exists once someone has signed up. An
  `application` holds `applicant_name` / `applicant_email` and **no user reference at
  all** (`reviewed_by` is the reviewer, not the applicant). So an approved application
  carries nothing that can populate `enrollments.user_id`.

  **The real chain is: Application approved → applicant invited → applicant signs up
  (`users` row created by the `on_auth_user_created` trigger) → Admin enrols them.** The
  middle step is what's missing. The `invitations` table exists for exactly it (email,
  invited_role, token, expires_at) and nothing is built on it yet.

  A "Create enrollment" button on an approved Application was deliberately **not** added:
  it would dead-end for any applicant without an account, which is the normal case
  immediately after approval. Better an honest gap than a button that usually fails.

  **Success criterion 3 — "An Application can go from public submission to enrolled
  Student without manual database work" — is therefore still not met.** The missing piece
  is the invitation/signup step, not the Enrollment screen. Whoever picks that up should
  reconcile this section and the Applications one.

- **The wireframe shows no create control on this screen**; one was added, because
  nothing else in Admin can produce an enrollment and the spec requires Admin to manage
  enrollment (feature #11). The wireframe has been updated to match.

- **Editing changes status and detail only** — never which student or which program. The
  table is unique on `(user_id, program_id)`, so moving either is a different enrollment,
  not an edit of this one. The edit form pins both as read-only and the Server Action
  validates against a narrower schema that has no such fields to write.

- **Completed and withdrawn are terminal in v1.** Edit appears only on active rows,
  matching the wireframe. Reversing a closed enrollment is out of scope.

- **Staff see no write controls at all**, not disabled ones — `enrollments_write` is
  Admin-only with no staff-write policy to fall back on, so their access here is
  genuinely read-only tracking. The write routes (`/enrollment/new`, `/enrollment/:id/edit`)
  refuse a non-Admin directly, since hiding a link is not authorization.

- **The student picker lists every account**, not only those holding a `student` role —
  which roles may be enrolled isn't settled anywhere, and inventing a filter would
  quietly hide people an Admin legitimately needs to enrol. Emails disambiguate.

### Applications — decisions made while building the screen

- **The Admin-only approval rule is now enforced in the database**, not just the UI.
  `002`'s `applications_update` policy let any Staff member write `status = 'approved'`,
  contradicting the confirmed decision above; `003_application_approval_rls.sql` adds the
  `WITH CHECK` that actually reserves approval for Admin. See
  `Bauhaven-Database-Schema.md`. Approval is checked in three independent places — RLS,
  the Server Action, and the rendered UI — because the first two are the authorization
  and the third is only presentation.

- **Staff never see the Approve button**, rather than seeing it disabled. An action a
  Staff member can never take is noise in a queue they work all day.

- **Status transitions are fixed:** Submitted → Confirmed → Approved, with Decline
  available from Submitted or Confirmed. Approved and Declined are terminal — reversing
  a decision is out of scope for v1. The transition is enforced as a filter on the
  update itself rather than a read-then-write, so two reviewers acting on the same row
  at once produce one decision and one "already actioned" message, not a silent
  overwrite.

- **Reviewing does not create an enrollment.** Approving sets `applications.status` and
  stamps `reviewed_by`/`reviewed_at`; turning an approved application into an
  `enrollments` row is Enrollment's job (feature #11, Admin-only) and is not wired up
  yet. Success criterion 3 — "an Application can go from public submission to enrolled
  Student without manual database work" — is therefore **not yet met**; it needs the
  Enrollment screen.

- **The public intake form is not part of this screen.** `applications_insert_public`
  exists for the Site to write into; Admin only ever reads and updates.

- **Submitted times display in `Africa/Douala`**, pinned rather than left to the server's
  timezone, so "Today, 09:12" means the same thing regardless of deploy region.

### Courses & Programs — decisions made while building the screen

These came out of implementing the Programs screen in `bauhaven-admin-web`; they resolve
points the feature list and the wireframe left open or disagreed on.

- **Retiring a program is an archive, never a row delete.** `programs.status` flips to
  `archived` and the row stays. This is the wireframe's "Archived" badge, and it's forced
  by the data model: `enrollments`, `applications`, `attendance_sessions`, `tasks`,
  `projects`, `portfolio_entries`, `testimonies`, `user_roles`, and `issue_reports` all
  carry a `program_id` FK, so deleting a program would orphan historical records that
  finance and attendance reporting depend on. Feature #2 (Delete Program, Admin-only)
  keeps its `programs_delete` RLS policy for a genuine data-entry mistake, but v1 ships no
  UI for it — the spec listing a delete and the wireframe offering only Edit was the one
  real conflict between the two documents, resolved in the wireframe's favour.

- **Archiving happens inside the edit form**, via the Status field — not a separate
  row action. Matches the wireframe, which gives each row only an Edit control.

- **Program fees are XAF-only in v1.** `fee_currency` is stamped `'XAF'` when a program
  is **created** and is not editable in the UI. The column stays for later, but
  `fee_amount_minor` holds *whole francs* for XAF (no minor unit) and *cents* for
  anything else — offering a currency picker without resolving that would put two
  different units in one column.
  **Editing a program never rewrites `fee_currency`.** If a row arrives from anywhere
  else — a seed, an import, the public Site — with a non-XAF currency, an admin edit
  leaves it alone rather than restamping it XAF and silently reinterpreting the amount
  (€450.00 stored as 45000 would otherwise resurface as 45,000 XAF).

- **Duration is stored and entered in days** (`duration_days`), and humanised for
  display only: exact multiples render as "12 weeks" or "6 months" to match the
  wireframe's Duration column, and anything that doesn't divide evenly stays in days
  rather than being rounded. Per-enrollment overrides (feature #4) still live on
  `enrollments.duration_override_days`.

- **Only the English title is required.** `title_fr`, both descriptions, duration,
  modules, and fee are all optional, so staff can create a program before the French
  copy exists rather than being blocked on a translation.

- **Create and edit are one form on their own routes** (`/programs/new`,
  `/programs/:id/edit`), not a modal: same fields and same validation either way, a
  deep-linkable edit URL, and no nine-field form trapped in a scrolling dialog at the
  360px floor.

- **The list's Type/Status filters run in the browser** for v1 — the whole catalog is
  a few dozen rows already fetched by the server component. Server-side filtering
  waits until the list outgrows a single page.

- **"Enrolled" counts active enrollments only** (`enrollments.status = 'active'`),
  excluding completed and withdrawn.

### Attendance — decisions made while building the screen

These came out of implementing the Attendance screen in `bauhaven-admin-web`.

- **This screen is Staff/Admin marking a roster, not self check-in.** Academy has its own
  check-in flow; both write to the same `attendance_records` table, which is why
  `attendance_records_insert` has two arms — a student inserting their own row must be
  actively enrolled in the session's program, while Admin/Staff recording on someone
  else's behalf skip that check because they aren't checking themselves in.

- **Marking is Admin *and* Staff**, unlike Enrollment. `attendance_records_insert` and
  `attendance_sessions_write` both gate on `auth_is_admin_or_staff()`, with no
  admin-only arm — taking a register is the Mentor/Supervisor's job, not the Founders'.
  Anyone else gets the roster read-only, with statuses as badges and no pills rendered.

- **Every mark is an INSERT. Re-marking is a correction row, never an edit.**
  `attendance_records` has no UPDATE policy at all, so this is enforced by the database
  rather than by convention — an `UPDATE` is rejected by RLS, not merely discouraged.
  Tapping a different pill for a student who is already marked appends a row whose
  `corrects_id` points at the row it replaces.

- **The row being corrected is resolved server-side at write time**, not sent by the
  browser. A `corrects_id` the client was holding is already stale if someone else
  marked the same student in between, and using it would fork the chain into two rows
  that both look current instead of extending it.

- **Re-clicking the pill a student is already on writes nothing.** The audit trail's
  whole value is that every row is a real decision; a correction that corrects nothing
  is noise.

- **Both the roster and the stat cards read through one resolution, in one place.** A
  plain `select` over a session double-counts every correction — a student marked Present
  then corrected to Absent lands in *both* stat cards. The rule is "the row nothing else
  supersedes", derived from `corrects_id`, not "the row with the newest `created_at`":
  two rows written in one statement share a timestamp exactly. `created_at` only breaks
  ties between rows that are all still standing, which happens when two staff mark the
  same student concurrently.

- **The roster has no roster table.** It's every user with an active enrollment in the
  session's program (`enrollments.status = 'active'`), so enrolling someone adds them and
  withdrawing them takes them off — nothing to keep in sync.

- **A session is one program on one date, and duplicates are refused.** There's no unique
  constraint on `(program_id, session_date)`, so the check is in the Server Action: two
  sessions for the same class on the same day would split its history in half with nothing
  to say which is the real record. The collision reports the existing session's id and the
  form offers to open it.

- **`checked_in_at` stays null on a staff-marked row.** It means "when this person checked
  in", which nobody did; `created_at` already records when the mark was made. The column is
  for Academy's self check-in.

- **The screen opens on today's session**, resolved in `Africa/Douala` rather than the
  server's day. With several today it takes the most recently created; with none today it
  falls back to the most recent past session (and says so) rather than jumping to one that
  hasn't happened yet. The selection lives in `?session=`, so a particular roster is a
  link, and switching sessions re-fetches server-side — a different session can mean a
  different program and therefore a different list of students.

- **Auto-excuse from an approved absence Request (feature #18's dependency) is not built.**
  The Requests approval flow doesn't exist in Admin, so there is no approved-absence state to
  derive anything from. *(Updated: `bauhaven-academy-web` now writes `requests` — students can
  submit absence requests, and Staff/Admin can read them, since `requests_select` covers them.
  What's still missing is the deciding half, and it's blocked in the database as well as in the
  UI: `requests` has no UPDATE policy for anyone, so no row can leave `'pending'`, and
  `request_approvals` has no INSERT policy, so no approver row can be created. See the Academy
  spec's "Requests" section for the full shape of the gap.)* All three statuses are set manually by Staff/Admin. Building
  half of Requests to fill the gap was rejected as worse than leaving it visibly absent; the
  gap is marked with `TODO(requests)` in `src/lib/schemas/attendance.ts` and at the roster
  query in `src/app/(app)/attendance/page.tsx`. When it lands, the auto-excuse belongs in the
  **read** path as a derived default for students with no record yet — a Staff override is
  then just an ordinary mark, and the append-only chain already makes the override win.

### Tasks — decisions made while building the screen

These came out of implementing the Tasks screen in `bauhaven-admin-web`. Two of them
resolve things neither the feature list nor the wireframe had settled.

- **A task is one row per student, and assigning to a cohort creates N of them.** This is
  forced by the schema, not chosen for convenience: `tasks.assigned_to` is singular *and*
  `tasks.status` is per-row, so a single row shared by a 28-student bootcamp could not
  have Sam graded while Fatima is still open. `submissions.task_id` would likewise
  collapse a whole cohort's work onto one task with one gradeable submission. The
  wireframe already assumed this — every row it shows is one task, one named student.

  So "+ New task" takes a program and a mode: **everyone actively enrolled** (the
  default) or **one student**. The cohort option says how many rows it is about to create
  before it creates them, because clicking a button once and finding 28 new rows is
  otherwise a surprise. Both modes source students from `enrollments` with
  `status = 'active'` — the same source as the Attendance roster — so a task can't be
  assigned to someone who isn't on the program.

  The cost, accepted: a cohort assignment puts 28 similarly-titled rows in a flat list.
  The wireframe's list is flat and this change doesn't alter that. Grouping identical
  titles into one expandable row is a real improvement and a separate one; it is **not**
  a reason to share a row at the database level, which would break per-student grading.

- **Writes are a single multi-row insert, not a loop.** PostgREST applies one statement,
  so a cohort assignment either lands whole or not at all. N sequential inserts would
  leave half a cohort holding the task with nothing to say which half.

- **`projects` is a real table this feature deliberately doesn't touch.** It has its own
  `title`, `description`, nullable `program_id`, `created_by`, and a
  `status in ('active','approved','archived')` — it's the approvable container behind
  feature #14 (Approve Project, Admin-only), not a grouping label on tasks.
  `tasks.project_id` exists and is nullable; every task Admin-web creates leaves it null.
  The wireframe's screen shows a flat task list with no project grouping, which matches:
  **the "& Projects" in the nav label is about where Projects will live, not about what
  ships now.** The label is kept for that reason. Building Projects means the entity's own
  create/approve flow, and it is not in this change.

- **The grade lives on `submissions.grade`, and it is free text.** It's the only column in
  the schema that can hold a grade — `tasks` has none, and `feedback.rating` is a 1-5
  integer that cannot express the wireframe's "Graded — 88%". So "88%", "A-", and "Pass"
  are all valid, and the UI doesn't invent a percentage-only rule the column doesn't have.
  `feedback.rating` is offered separately and optionally, labelled as what it is.

- **Grading was impossible under `002` and needed a migration.** `submissions` had `SELECT`
  and `INSERT` policies and no `UPDATE`, so nothing could ever write `submissions.grade`
  — features #5 and #17, both Must, were unimplementable as specified. Fixed in
  `004_submission_grading_rls.sql` with an admin/staff-only `submissions_update`,
  deliberately not extended to the submission's owner (a student able to update their own
  row could rewrite their own grade, and `submissions` has no correction chain to make
  that visible). Third instance of the policy-versus-spec class of bug, after the RLS
  recursion issue and `003`.

- **Grading is three writes and PostgREST offers no transaction across them**, so the
  order is chosen for what a partial failure leaves behind: `submissions.grade` first (a
  retry rewrites the same value), then the `feedback` row (the table has no unique
  constraint — several comments on one submission are the design), then
  `tasks.status → 'graded'` last. Any earlier failure therefore leaves the task **still
  Submitted** — still in the queue, still showing its "Give feedback" action — rather than
  hidden as Graded with nothing on it. The transition is guarded with
  `.eq('status','submitted')` so two staff grading at once means the second is told
  someone beat them to it, not that it silently re-grades.

  **Known limitation, not solved here:** the three writes can still tear. Making them
  atomic means a Postgres function called over RPC, which is a migration and a change to
  how every mutation in this app is shaped — worth doing, and out of scope for the screen
  that surfaced it.

- **"View" and "Give feedback" are one route,** `/tasks/:id`. The submission link, the
  feedback history, and the grading form are the same page's content, so a separate
  grading route would be that page under a second URL. Only a Submitted task gets the
  wireframe's "Give feedback" wording and a solid button; the rest say "View".

- **`content_url` opens in a new tab with `rel="noopener noreferrer"`.** It's
  student-supplied and points off-site, and a grader halfway through writing feedback
  shouldn't lose it by navigating away.

- **Deadlines are entered and read in `Africa/Douala`.** `tasks.deadline` is a
  `timestamptz` but the form collects it with `datetime-local`, which hands back
  wall-clock time and no zone. Reading that as Bauhaven's zone happens in one place
  (`bauhavenLocalToInstant`); a deadline typed as 11:59pm and stored as 11:59pm UTC would
  be an hour late, and invisible until someone submitted in the gap.

- **`archived` is a real `tasks.status` value with no tab and no UI.** The wireframe's
  filters are All/Open/Submitted/Graded, and feature #15 is a *delete* by the creator, not
  an archive. Rows that arrive archived still render with a label; nothing in Admin-web
  sets that status.

### Finance — decisions made while building the screen

These came out of implementing the Finance screen in `bauhaven-admin-web`.

- **Access is gated at the navigation level, not just inside the page.** Finance is the
  only module in Admin-web where the sidebar link is conditional. Everywhere else, Admin
  and Staff both see the screen and the *actions* are gated (Staff see the Enrollment
  list but no Edit button). Here, someone with no finance grant never learns the screen
  exists — because RLS would hand them an empty result set, and an empty ledger shown to
  someone who simply can't see the rows is a false statement about the books. Three
  distinct states, three distinct messages:
  **no access** (a plain explanation and who can grant it — not a 404, since the link is
  already hidden, so anyone reading it typed the URL), **view-only** (reached the record
  route with a view grant but no create grant), and **no records yet** (a permitted user
  looking at a genuinely empty ledger, with the way to add the first one).

- **The permission check calls `auth_has_permission` over RPC rather than reading the
  tables.** It has to: `permissions` and `user_permission_overrides` are both
  `for all using (auth_is_admin())`, so a Staff member cannot read their own grant. The
  app therefore *cannot* compute this from table data as the user in question, and
  re-implementing the precedence in TypeScript (individual override beats role default
  beats false) would be a second copy of the rule free to drift from the SQL. Calling the
  same `security definer` function the policy calls means the nav gate and the database
  cannot disagree. It reports on `auth.uid()` only and cannot be asked about anyone else.
  Fails **closed** — an unreachable permission check is not a grant.

- **Viewing and recording are separate grants**, because `finance_select` and
  `finance_insert` are separate policies. Someone can hold `finance:view` without
  `finance:create`.

- **Approval is a single Admin, confirmed against the schema.** `finance_records` carries
  one nullable `approved_by` plus `approved_at`. The multi-approver quorum described for
  absence Requests lives in a *separate* `request_approvals` table, unique on
  `(request_id, approver_id)`, precisely because that flow needs several approvers and
  this one doesn't. Two mechanisms, not one — now stated outright in
  `Bauhaven-Database-Schema.md`, since `Bauhaven-Development-Plan.md` had described "the
  finance approval-quorum logic", which doesn't exist. That line is corrected.

- **Approval has no grantable arm.** There is no `auth_has_permission('finance','approve')`
  anywhere in `002`, so a Staff member with full finance access still cannot approve — and
  gets no button at all rather than a disabled one. That's the separation of duties the
  payer → recorder → approver chain exists to enforce, and it's why `status` is never
  taken from the caller when recording: everything starts `pending`, so nobody can record
  a transaction pre-approved for themselves.

- **Approval needed a migration, and it isn't a relaxation of append-only.** `002` gave
  `finance_records` no `UPDATE` policy at all. That's right about the money and wrong
  about approval: it left `status`, `approved_by` and `approved_at` permanently at their
  defaults, making feature #21 unimplementable.
  `005_finance_approval_rls.sql` grants exactly one UPDATE — pending → approved, by an
  Admin, naming themselves — and *tightens* the money at the same time, via column-level
  privileges that make `amount_minor`, `description`, `type`, `payer_*`, `recorded_by`,
  `corrects_id` and `created_at` unwritable by any app session. Append-only for the money
  is now a Postgres privilege rather than the absence of a policy. Modelling approval as
  an insert with `corrects_id` was considered and rejected: `corrects_id` means "that row
  was wrong", and an approval is a decision about a transaction that isn't.

- **No reject, and no edit.** `status` is `check (status in ('pending','approved'))` with
  no third value. A transaction that shouldn't stand is corrected by a new row. Approved
  rows carry no action control at all — matching the Enrollment precedent, since there is
  no finance detail screen for a "View" to lead to.

- **The correction resolver is shared with Attendance, not re-derived.**
  `src/lib/append-only.ts` is one generic collapse over `(id, corrects_id, created_at)`;
  Attendance partitions per student before calling it, Finance resolves the whole ledger.
  Everything downstream — the table, the filter tabs, and both stat cards — reads from
  that one resolved array, so there is no second path that could count a superseded row.
  A 50,000 corrected to 45,000 sums to 95,000 from the raw table; that's a test, not just
  a warning.

- **The superseded row is dropped from the list and the replacement is flagged
  "(correction)".** Showing both would double the ledger visually even with correct
  totals; showing neither would make it look like a transaction vanished.

- **Payer is free text *and* an optional account link, not one or the other.**
  `payer_name` is "always captured, even if `payer_id` is null" per the schema's own
  comment — it's a snapshot of the name at transaction time, deliberately independent of
  whether the account or its name changes later. Free text is load-bearing rather than a
  fallback: the wireframe's own example is a batch payment by **"12 students"**, which is
  not one account and never will be. Choosing an account prefills the name and leaves it
  editable; a linked payer with no name is rejected.

- **Amounts are whole francs and are never scaled.** XAF has no minor unit, so
  `amount_minor` holds francs — the input is `step=1`, the schema rejects fractions
  rather than rounding someone's money, and nothing multiplies or divides by 100 on the
  way in or out. Formatting reuses `formatFee`, so the ledger and the program-fee column
  cannot start disagreeing about what the number means.

- **Month-to-date income is Cameroon's month and includes unapproved rows, and says so.**
  A payment at 00:30 WAT on the 1st belongs to the new month; read in UTC it would fall
  out of the total. Money that came in is money that came in — hiding it until an Admin
  signs off would make the figure lag reality, so the card carries "Includes transactions
  not yet approved" whenever it does.

- **Only two stat cards, deliberately.** Pending count and month-to-date income. Charts,
  trends, and expense breakdowns are Phase 2 per `Bauhaven-Development-Plan.md` and are
  not in this pass.

- **The table breaks to cards at `lg`, not `md` like every other list.** The Chain column
  is three names and two arrows, so this table needs noticeably more width before it
  stops being readable. Below that the chain stacks vertically with a ↓ — the only way it
  fits 360px without truncating a name, and a truncated name in an audit trail defeats
  the column. The whole chain also carries one screen-reader sentence ("Sam Student paid,
  Sue Staff recorded, awaiting approval"), because read as separate fragments it loses the
  sequence that is the entire point.

- **`receipt_ref` is not collected yet.** The column exists on `finance_records` and is a
  real audit affordance, but it isn't in the wireframe's form or this pass's scope. Worth
  adding when receipts are actually being filed; noted here so its absence is a decision
  rather than an oversight.

### Assets — decisions made while building the screen

These came out of implementing the Assets screen in `bauhaven-admin-web`. The first one
resolves a question no document had answered.

- **`status = 'retired'` is a status. It is not a soft delete, and this screen never
  writes `deleted_at`.** `assets` carries both, and they mean different things: retired is
  end-of-life but still inventory; `deleted_at` means the row shouldn't be in the
  inventory at all (created by mistake, a duplicate).

  **Admin-native settles this rather than preference.** Its Assets tab is a field lookup
  that renders a `Retired` badge in its ordinary list, and its own note says *"Status
  updates (e.g. marking 'needs repair') work here; creating new assets or reassigning them
  stays on the web app."* So Admin-native both displays retired assets and writes
  `status` — it has no delete capability at all. If retiring on the web set `deleted_at`,
  the row would disappear from a screen whose wireframe shows it, and Admin-native's
  status-update action could never produce that state. Full comparison table in
  `Bauhaven-Database-Schema.md`.

  Consequently: reads filter `deleted_at is null` and deliberately do **not** filter out
  `retired`. The edit route excludes soft-deleted rows so a stale tab can't resurrect one,
  but includes retired ones.

- **Retiring is reversible, and the retired row keeps its Edit control.** The wireframe
  originally showed "View" on that row; nothing in the schema makes `retired` one-way, and
  Admin-native can change a retired asset's status from the field — so a terminal-on-web
  interpretation would be a restriction the other app doesn't share and can't honour.
  There is also no asset detail screen for a "View" to lead to, the same reason Enrollment
  dropped its own. Wireframe updated.

- **No delete UI, soft or hard.** Neither the feature list (#24, #25) nor the wireframe
  has one, so none shipped — the same resolution Programs reached. Worth knowing when one
  is eventually built: `assets_write` is `for all`, so RLS *does* permit a hard `DELETE`,
  but `issue_reports.asset_id` references `assets(id)` with no `ON DELETE` clause, so any
  asset with an issue report against it is `RESTRICT`-protected. That FK is itself the
  argument for making that future control a soft delete.

- **The write gate is flat Admin/Staff, with no override to account for.** Unlike Tasks
  (`auth_has_permission('tasks','create')`) and unlike Finance (granted per person
  entirely), `assets_write` is `for all using (auth_is_admin_or_staff())` with no
  permission arm at all. That matches the confirmed decision above — a student appearing
  as an Asset creator in the source document was unintentional. So the refusal message is
  deliberately final ("this isn't something that can be granted individually") rather than
  pointing someone at a request that can never be granted.

- **The nav link stays visible to everyone**, unlike Finance's. Asset management isn't a
  per-person grant, so there's nothing whose existence needs hiding; someone without
  access gets an explanation rather than an empty inventory, which would read as
  "Bauhaven owns nothing" instead of "this isn't yours to manage".

- **Reading is wider than writing in RLS, and Admin-web doesn't build on that.**
  `assets_select` also admits `assigned_to = auth.uid()`, so someone holding an asset can
  see that one row. This screen is a management view rather than a "my equipment" view, so
  it doesn't surface that — but it's why a student reaching `/assets` is told what the
  screen is rather than shown an error.

- **The assignee picker offers every account, unfiltered by role.** `assets.assigned_to`
  has no role constraint and a projector goes to whoever has it; restricting the list
  would invent a rule the schema doesn't have.

- **Type is editable after creation.** An asset created as physical when it was digital is
  a mistake to fix, not a different asset — nothing here is keyed on identity the way an
  enrollment's student/program pair is.

- **The Type/Status toolbar is two real `<select>` controls**, not the buttons the
  wireframe draws — the same treatment Enrollment's filters got, and for the same reason:
  a native select brings keyboard handling and mobile pickers for free.

- **`assets` has no `created_by` column**, so unlike a task or a finance record there is
  nothing to stamp the author onto. The audit trail here is `created_at` plus the
  `updated_at` trigger, and that's all the schema offers. Noted so its absence reads as
  the schema's shape rather than an omission in this screen.

### Content Editor — decisions made while building the screen

These came out of implementing the Content Editor in `bauhaven-admin-web`, the last
screen in M2.

- **The publish rule: every field is filled in both languages, or in neither.** The
  schema can't express this — `title_fr`, `body_fr`, `description_fr` are all nullable on
  purpose so a draft can be saved mid-sentence — so it's an app-level gate that applies
  only at publish:
  - **Saving a draft** needs nothing but the English title (`title_en` is the one
    `not null` text column). Half-written work is the normal state of a draft; refusing to
    save it would mean losing it.
  - **Publishing** requires parity. A page live on a bilingual site with an empty French
    body doesn't degrade gracefully — a French visitor gets a blank section, which is
    worse than the page not being there. The Development Plan's own definition of done
    says as much: "EN and FR both checked… a screen that only works in English isn't done."

  "Or in neither" keeps the rule from being a nuisance: a page with no body at all is
  perfectly publishable. Only a field written in *one* language is refused. The rule is
  symmetric — French without English is just as much a hole — and every gap is reported
  at once rather than one per attempt.

- **The EN/FR tabs are one form, with both panels mounted.** Only the inactive panel is
  `hidden`, which keeps its inputs registered with react-hook-form (switching tabs must
  not lose typing) and out of the accessibility tree (a screen reader shouldn't be read
  two copies of every field). Real `tablist`/`tab`/`tabpanel` semantics, unlike the filter
  "tabs" elsewhere in Admin-web, which filter a list in place and use `aria-pressed`. A
  language with a half-filled field gets a marker on its tab, because the failure this
  screen exists to prevent is publishing without noticing the other tab is empty.

- **The webhook cannot fail a publish, and that's tested rather than assumed.** The
  database write commits first and independently; `revalidateSitePaths` never throws, and
  the publish action wraps it anyway — depending on another module's promise not to throw
  is not the same as not throwing, and by that point the row is already published. A
  failure surfaces as the soft notice the Architecture Plan specifies ("Published — the
  live site may take a few minutes to catch up"), announced as a `status`, not an `alert`.
  Reading that out as an alert would tell someone their work failed when it didn't.

- **`skipped` is a third outcome, distinct from `failed`.** With no
  `SITE_REVALIDATE_URL`/`SECRET` configured, publishing works and says nothing was
  refreshed. An Admin running against no Site is a normal local state, and reporting it as
  a failure trains people to ignore the warning that matters.

- **Portfolio entries revalidate the index only.** The Architecture Plan's contract
  example shows a per-entry path (`/portfolio/a-booking-platform-…`), but
  `portfolio_entries` has **no slug column** — so Admin has nothing to build that path
  from, and a uuid-based guess would ask Site to revalidate a route that may not exist.
  **This is an M6 dependency:** per-entry revalidation needs `slug` added to
  `portfolio_entries` first. Flagged in the Architecture Plan rather than papered over.

- **`slug` is not editable.** It maps a `pages` row to a route on the live Site, so
  changing it silently breaks a URL that already exists in the wild and in search results.
  Renaming a route is a Site code change, not a content edit. `pagePath()` maps slug
  `home` to `/` — the one slug→path rule Admin has to guess at, to confirm at M6.

- **Pages can't be created here; portfolio entries can.** Asymmetric on purpose. A `pages`
  row whose slug matches no Site route is content nobody can reach, so a page is created
  alongside its route in the Site's code. Portfolio entries have no such constraint and
  Admin-web is the **only** surface that will ever create one — the Academy spec rules out
  self-publishing outright ("that's the Site's Portfolio feature, curated by Admin/Staff,
  not self-published here"). Everything created here starts as a draft; `status` is never
  taken from the caller.

- **No consent field on `portfolio_entries`, deliberately.** The Project Brief lists
  Portfolio consent under "Known open items" as explicitly deferred, so Admin/Staff
  curation remains the only gate and adding an opt-in column would settle a decision left
  open on purpose. The editor says so in plain words beside the student picker rather than
  pretending the question doesn't exist. Asserted in tests so it can't drift back in.

- **Three sidebar toggles became one status, and Preview was dropped.** Of the wireframe's
  "Visible on live site" / "Show in FR" / "Featured on homepage", only the first has a
  column (`status`). The other two need schema that doesn't exist, and "Show in FR" would
  contradict the publish rule outright. "Featured portfolio entries" is a page→entry
  relation the schema can't express. "Preview" is dropped because no preview route is
  specified anywhere — the revalidation webhook is the only Site contract that exists, and
  inventing a second one is out of scope. Wireframe updated.

- **Unpublishing exists, and revalidates too.** Content someone has decided shouldn't be
  public, still being served from Site's cache, is the more urgent staleness of the two.
  `published_at` is deliberately left alone — it records when this was last made public,
  which stays true after it comes down.

- **Blog and `content_blocks` are not here.** Blog shares the wireframe's "Website" nav
  section but is Phase 2 per the Architecture Plan's roadmap; the Development Plan is
  explicit that building Phase 2 work alongside M0–M6 is scope creep against an agreed
  roadmap. `content_blocks` has no status of its own and goes live with its page, and
  nothing in the wireframe edits one.

- **`.env.example` did not exist**, despite the README's setup step 2 telling people to
  copy it. Created, with both Supabase keys and the two revalidation variables documented
  — including why `SITE_REVALIDATE_SECRET` has no `NEXT_PUBLIC_` prefix.
