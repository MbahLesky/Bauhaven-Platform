# Bauhaven Academy — Feature Specification

## 1. Problem & background

Academy is the single Intern/Student/Holiday-maker-facing app: a dashboard where they see their timeline, tasks, deadlines, performance, and attendance, and can submit work, report problems, request leave, and manage their profile. It deliberately carries none of Admin's finance/asset/course-management capabilities — different user base, different risk profile, and a simpler, likely mobile-friendly UI.

## 2. Users

- **Intern**
- **Student**
- **Holiday/Bootcamp participant**

All modeled as `UserRole` rows in Core — a person can hold more than one of these at once (or one of these plus a Staff role elsewhere), and Academy's profile switcher (shared from Core) handles that case.

## 3. User stories

**Dashboard & Profile**
- As a User, I want to see a dashboard when I log in showing my current programs and timeline (duration, fees where relevant).
- As a User, I want to switch between profiles if I hold more than one active role (e.g. Intern + Student).
- As a User, I want to update my profile: photo, preferred language, contact info.

**Courses/Programs**
- As a User, I want to see the Programs I'm enrolled in and take the courses/projects/tasks assigned to me.
- As a User **with permission granted**, I want to create my own Task/Project to track independent work.

**Tasks & Submissions**
- As a User, I want to see my assigned Tasks and deadlines.
- As a User, I want to make a Submission against a Task.
- As a User, I want to see Feedback/grades on my Submissions.

**Attendance**
- As a User, I want to submit/check in my attendance for a session.
- As a User, I want to see my attendance statistics.
- As a User, I want to submit an absence/unavailability Request so my absence gets recorded and excused.

**Performance**
- As an Intern/Student/Holiday-maker, I want to see my performance (aggregated grades/feedback) so I know how I'm doing.

**Testimonies & Issue Reporting**
- As a User, I want to submit a Testimony about my experience.
- As a User, I want to report a problem so Staff can address it.

**Blog** *(shared with Admin/Site)*
- As a User, I want to add a Blog post, understanding it needs Admin/Staff approval before it's public.

## 4. Feature list

| # | Feature | User(s) | Priority | Notes |
|---|---|---|---|---|
| 1 | Dashboard: timeline based on registration (duration/fees) | All | Must | |
| 2 | Profile switcher (if >1 active role) | Multi-role users | Must | Shared component from Core. **Not built** — auth shipped without it deliberately; it needs a real "acting as" session concept and screens that vary by role. Stays M3 scope, see `Bauhaven-Architecture-Plan.md` §6, "Auth as built" |
| 3 | Profile management (photo, language, contact) | All | Must | |
| 4 | View enrolled Programs/courses | All | Must | |
| 5 | View assigned Tasks & deadlines | All | Must | |
| 6 | Create own Task/Project (if granted permission) | Permission-gated | Should | Gate confirmed in Admin's spec |
| 7 | Make Submission | All | Must | |
| 8 | View Feedback/grades on Submission | Intern, Student | Must | |
| 9 | Submit attendance (check-in) | All | Must | **Web: online-only**, plain error + retry on failure. Cache-and-queue is the *native* client's capability (Drift) — see `Bauhaven-Architecture-Plan.md` §3 and §8, "Attendance" |
| 10 | View attendance statistics | All | Must | |
| 11 | Submit absence/unavailability Request | All | Must | Entity owned by Core, submitted here. **Submission built; approval doesn't exist yet and is blocked by missing RLS — see §7, "Requests"** |
| 12 | View performance summary | All | Must | Confirmed to include Holiday-makers |
| 13 | Submit Testimony | Intern, Student, Holiday-maker | Should | |
| 14 | Report an issue | All | Must | **Submission built; no Staff triage/resolution screen exists anywhere — see §7, "Issue reports"** |
| 15 | Add Blog post (pending approval) | All | Could | Shared with Admin/Site |

## 5. Out of scope — v1

- Peer-to-peer messaging/chat between Users.
- In-app payment for courses/services (future, Phase 3, lives in Admin).
- Self-published public profile pages — that's the Site's Portfolio feature, curated by Admin/Staff, not self-published here.

## 6. Success criteria

- A User can complete the full loop — view task, submit work, see feedback, check attendance — without contacting Staff manually.
- Absence Requests submitted here reach the correct approver without manual follow-up.
- Dashboard is usable on a low-end Android device, given the likely user base — worth naming as an explicit testing target.

## 7. Constraints, risks & open questions

*(none outstanding — all resolved below)*

### Tasks — decisions made while building the screen

These came out of implementing Academy's Tasks screen, the other half of Admin-web's.

- **Submitting moves the task to `submitted` via a database trigger, not via this app.**
  The two apps had incompatible assumptions and the answer turned out to be "nobody does
  it": Admin-web reads the submitted state but never writes it, Academy inserts the
  `submissions` row, `tasks_update` is `created_by = auth.uid()` so an *assigned* student
  can't touch the task, and no trigger existed. A submission would have left the task
  `open` forever — invisible in Admin's queue and ungradeable, silently on both sides.
  Fixed in `006_submission_marks_task_submitted.sql`; full reasoning in
  `Bauhaven-Database-Schema.md`.

- **A submission is a link, because that's all the column is.** `submissions.content_url`
  is the only column carrying the work — no file storage, no body text — so submitting
  means pointing at something hosted elsewhere. The schema allows it to be null; this
  screen requires it, since a submission with no link tells a grader nothing.

- **Badge colours were corrected to match Admin-web.** The wireframe had Open as
  `warning` and Grading as `neutral` — the inverse of Admin's — so the same task changed
  colour depending on which app you opened. Admin's reading is the semantically correct
  one: Open is neutral (nothing wrong, just work to do), Grading is warning (waiting on
  someone), Graded is success and carries the grade itself.

- **"Draft" was not a real status.** `tasks.status` is
  `open`/`submitted`/`graded`/`archived`; a self-created task is simply `open`. It's
  distinguished by a "Self-created ·" prefix on its meta line, matching Admin-web's
  treatment, rather than by a status that doesn't exist. Wireframe corrected.

- **"+ New task" is hidden, not disabled**, for anyone without the individual
  `auth_has_permission('tasks','create')` override — the same principle as Admin-web's
  role-gated controls. The check goes through the RPC rather than a table read, because
  `user_permission_overrides` is admin-only and a student physically cannot read their own
  grant. Fails closed; re-checked in the Server Action, since a direct POST doesn't pass
  through the UI.

- **A self-created task is assigned to its creator, both from the session.** Taking either
  from the client would let someone assign work to a stranger. Status is never taken from
  the caller either — everything starts `open`.

- **The Home preview and the Tasks screen share one query module.** They were already
  diverging on deadline rendering: Home used `toLocaleDateString`, which formats in the
  browser's zone and told a travelling student the wrong day, while Admin-web renders
  deadlines in `Africa/Douala`. Both now read through `task-queries.ts` and format through
  the same helper.

- **Neither screen filters by `assigned_to`.** `tasks_select` already scopes to
  `assigned_to = auth.uid() or created_by = auth.uid()`, so an explicit filter would
  duplicate the policy — and would also hide self-created tasks, which match on
  `created_by`, not `assigned_to`.

### Attendance — decisions made while building the screen

These came out of implementing Academy's self-check-in, the other half of Admin-web's
roster marking.

- **No offline queue on web, and the wireframe's promise of one was removed.** The card
  read "Works offline — syncs when you're back online". Academy-web cannot honour that:
  `Bauhaven-Architecture-Plan.md` §3 gives web clients best-effort caching and reserves
  queued writes for the native clients' Drift storage. A web page can't guarantee a queued
  write ever syncs — the tab closes, the browser evicts storage, there's no durable
  background sync in this stack — and for attendance a false "saved, will sync" is the
  worst available failure: the student believes they're present and the register says
  otherwise. The card now says "Needs a connection… nothing is saved until it succeeds",
  and a failure is a plain error with a retry. There's a test asserting the old wording
  never comes back.

  This also surfaced a contradiction inside §3 itself — one line gave web best-effort
  caching, the next said attendance queues "regardless of client". Corrected there.

- **A rejection from `attendance_records_insert` is a handled outcome, not a bug.** The
  policy's self arm is `user_id = auth.uid() and auth_enrolled_in_session_program(...)`,
  tested live earlier in the project. The page already scopes sessions to the student's
  enrolled program, so a refusal shouldn't normally happen — but the policy is the
  authority, not the page's query, and they can disagree (an enrolment withdrawn between
  load and tap, a stale tab). It's caught and explained, and points at the person who can
  fix it: a mentor, who *can* mark the student present because Staff bypass the check.

- **Check-in is three outcomes, not ok/error.** Success, already-recorded, and refused
  mean genuinely different things to someone standing in a doorway. "Already recorded" is
  announced as a `status`, not an `alert` — nothing failed and nothing was lost, and
  telling a student their attendance failed when it had already recorded is the wrong way
  round.

- **The duplicate check is the app's job, because the schema has no unique constraint.**
  `attendance_records` has no unique index on `(session_id, user_id)`, so a second insert
  would succeed and leave two standing rows for one session — exactly the double-count the
  append-only correction chain exists to prevent, inflating the student's own rate. The
  action resolves the existing record first and writes nothing if one stands.

- **Self-check-in only ever writes `status = 'present'`, and never a correction.** Marking
  yourself absent or excused asserts something only Staff can decide, and the policy
  doesn't distinguish statuses — so the restriction lives in the app. `corrects_id` is
  always null: adjusting attendance is a Staff override.

- **`checked_in_at` is stamped here and left null by Admin-web.** That's what keeps a real
  self-check-in distinguishable from a row Staff recorded on someone's behalf.

- **Excused sessions are excluded from the attendance rate's denominator**, not counted as
  absences: present ÷ (present + absent). An approved absence is the system saying "this
  one doesn't count against you", so folding it in would make excusing pointless and
  quietly punish a student for using the Requests flow correctly. **This changes the
  number the Home screen previously showed** — it computed `present ÷ all rows`, which
  both counted excused absences against the student *and* double-counted Staff
  corrections. Both screens now share one function.

- **The wireframe's "Today's session: 9:00am – 1:00pm" was removed.**
  `attendance_sessions` has `session_date` only — no start or end time — so those hours
  were not representable. Adding time columns is a schema change nobody has asked for; the
  screen shows the session's date instead.

- **Sessions are the one thing RLS doesn't scope.** `attendance_sessions_select` is
  `using (true)`, so every authenticated user can read every session. Unlike `tasks` or
  `attendance_records`, this query genuinely has to filter by `program_id` itself.

### Requests — decisions made while building the screen

These came out of implementing the absence-request screen (feature #11) in
`bauhaven-academy-web`. **Submission only** — see the gap at the end of this section.

- **The approval half is missing in the database, not just in the UI.** This is the point
  worth carrying forward. `requests` has a SELECT policy and an INSERT policy and *nothing
  else*: no UPDATE, so no row can ever leave `'pending'`, by anyone, including an Admin.
  `request_approvals` has SELECT and UPDATE policies but **no INSERT**, so no approver row
  can be created either. So building an Admin approval screen is not only a UI task — it
  needs a migration first, in the same family as `004_submission_grading_rls.sql` and
  `005_finance_approval_rls.sql`. That migration is deliberately *not* written yet, because
  its `with check` clause has to encode the quorum rule, and quorum is exactly the part
  nobody has designed: see the two open questions below.

- **No `request_approvals` rows are created at submission.** The table needs one row per
  required approver, and who those approvers are depends on routing that doesn't exist —
  the Core spec (§8) says a User's request needs one Staff approval, but nothing says
  *which* Staff member, and `users` has no supervisor link to derive it from. Whether rows
  are created eagerly at submission or lazily when a Staff member first opens a queue is a
  decision belonging to the approval screen; guessing here would seed rows that screen then
  has to work around.

- **`status` is not sent on insert at all.** The column defaults to `'pending'`
  (`001_initial_schema.sql` line 140 — checked, not assumed). Beyond ordinary
  don't-write-what-the-schema-owns hygiene, this matters because the quorum rule
  auto-approves when the company has exactly one Admin (zero *other* Admins = quorum
  trivially met). Whatever eventually implements that — a trigger, a different default, an
  edge function — would be fighting a client that hardcoded `'pending'`.

- **`type` *is* sent, explicitly `'absence'`.** The column has a default but no check
  constraint, so any text would be accepted. What the student is asking for is a fact this
  client knows; where it sits in a workflow is not. That's the line between the two.

- **`reason` is required by the form though the column is nullable.** A request with no
  reason gives the person deciding it nothing to decide on, and `requests` has no comment
  thread for them to ask a follow-up through. Same call, same reasoning, as
  `submissions.content_url`.

- **There is no cancel or edit control, because there could not be one.** With no UPDATE or
  DELETE policy on `requests`, a student cannot withdraw a request they've sent. A control
  that always failed would be worse than its absence — so the screen doesn't offer one, and
  the form warns about the range length instead (a mistyped year would otherwise sit in the
  queue uncorrectable).

- **The screen says approvals aren't handled in the app yet, in as many words.** Submitting
  is genuinely useful today: `requests_select` lets Staff and Admin read every request, so
  the information reaches them. What doesn't exist is anywhere to record a decision.
  Implying one is coming would be the same class of promise as Attendance's since-removed
  "works offline — syncs when you're back online".

- **The wireframe's "Goes to your Programme Manager for approval" was corrected** to "Goes
  to staff for approval". *(Correction to the note first written here: `programme_manager`
  **is** a real value — it's one of `user_roles.staff_sub_role`'s options, alongside
  auditor/coordinator/mentor. The earlier claim that the schema has no such role was
  wrong. The substantive reason for the change stands: nothing connects a student to a
  particular programme manager — `user_roles.program_id` scopes a **staff** member to a
  program, and there is no reverse lookup or supervisor link — and the quorum rule routes
  a User's request to one *Staff* approval, not to a named person. So the screen cannot
  promise a specific individual.)*

**Two-sided gap, for whoever picks up Requests-approval next.** Both halves are open and
they're the same feature:
1. *This side* — no approval screen exists anywhere (Admin-web's feature list has skipped
   it), and the RLS above has to land before one can work.
2. *Admin-web's Attendance* — feature #18's auto-excuse from an approved absence Request is
   marked `TODO(requests)` in `src/lib/schemas/attendance.ts` and at the roster query,
   because there was no approved-absence state to derive from. Approvals landing is what
   unblocks it, and the Admin spec's Attendance section already records where the auto-excuse
   belongs when it does (the **read** path, as a derived default for students with no record
   yet, so a Staff override stays an ordinary mark).

### Issue reports — decisions made while building the screen

These came out of implementing the "Report a problem" screen (feature #14) in
`bauhaven-academy-web`. **Submission only** — see the gap at the end of this section.

- **"Routed to Staff by category" is not a routing mechanism. The category is a label.**
  This was checked against the migrations rather than taken from the Core spec, and the
  spec's wording overstates what exists. The word "category" appears in exactly two places
  in the entire schema: the `issue_reports.category` column (`text not null default
  'general'`, **no check constraint**) and the composite index
  `idx_issue_reports_status_category`. There is no per-category staff assignment table, and
  nothing connects a category to `user_roles.staff_sub_role` or to a permission.
  `issue_reports_select` and `issue_reports_update` both gate on plain
  `auth_is_admin_or_staff()` with **no category arm** — so every Staff member and every
  Admin can read *and resolve* every report, whatever its category. The index is there so a
  triage screen can filter and sort; that's the whole of it. Real routing would need a
  category→staff mapping table or a category arm in the policies, and neither was built
  speculatively. The Core spec's confirmed decision is annotated accordingly.

- **Categories are a fixed list chosen here, because nothing upstream enumerates them.**
  With no check constraint, free text would put every report in a category of one —
  unsortable for whoever eventually triages, and useless against the index the schema
  already carries. The five: **Equipment or facilities** (`equipment`, the wireframe's own
  example), **Course or program** (`program`), **Account or access** (`access`), **Safety or
  wellbeing** (`safety`), **Something else** (`general`). The first two mirror what the
  schema already anticipates — `issue_reports` carries a nullable `asset_id` and a nullable
  `program_id`, which is the schema saying the two expected kinds of problem are "a thing is
  broken" and "something about my course". `general` is kept verbatim because it is the
  column default, so a row written by anything that doesn't set the column lands in a bucket
  the screen actually displays. Stored values are stable lowercase identifiers, never the
  display strings: a triage filter should match `'equipment'`, and the label has to be
  translatable EN/FR without rewriting rows.

- **Safety is its own category, and the screen is explicit that it doesn't summon anyone.**
  It earns a category so a Staff member scanning a list sees it without opening rows. But
  since nothing routes by category and no triage screen exists, the screen tells the student
  to tell a mentor directly as well rather than wait — the category cannot do work the
  system doesn't do.

- **`status` is not sent on insert.** The column defaults to `'open'`
  (`001_initial_schema.sql` line 174 — checked, not assumed) with a check constraint of
  `open`/`in_progress`/`resolved`. **Three states, not two** — Academy's row type had it as
  `open | resolved`, which would have made a triaged report an impossible value the moment
  anything set it. Fixed, and all three are rendered ("Open", "Being looked at", "Resolved").

- **`asset_id` and `program_id` stay null.** Both exist and are FK'd, but `assets_select` is
  `assigned_to = auth.uid() or auth_is_admin_or_staff()` — a student can read only the assets
  signed out to them, which is not who reports a broken projector in a shared room. Attaching
  either belongs to a triage screen, which is where that knowledge lives.

- **`reporter_id` is filled from the session, never from client input**, with a test for it.
  `issue_reports_insert` would refuse a forged one, but a report filed in someone else's
  name is a bad enough outcome that the app shouldn't depend on the database catching it.

- **Read-only list, no edit or withdraw.** `issue_reports_update` is
  `using (auth_is_admin_or_staff())`, so a student cannot amend a report they've filed.

**Unlike Requests, this gap is only a missing screen.** `issue_reports_update` already
exists and already lets any Admin or Staff member move a report through
open → in_progress → resolved. No migration is needed. What's missing is a Staff-facing
triage view — which appears in Admin-web's sidebar wireframe *with a count badge* (and on
its dashboard as an "Open issue reports" stat and in its activity feed), so it was always
intended, but it has never been queued in this project's build sequence.

### Three open threads, all pointing at the same missing surface

Worth raising before Academy-web's remaining scope (Testimony, Profile) gets built further
ahead of Admin-web. These are not three unrelated TODOs — they're one absent
**approvals/triage surface in Admin-web**, seen from three sides:

| Thread | Where it's blocked | Needs a migration? |
| --- | --- | --- |
| **Requests approval** | No screen; and `requests` has no UPDATE policy, `request_approvals` no INSERT | **Yes** — and the quorum rule and approver-routing have to be designed first |
| **Attendance auto-excuse** (Admin-web feature #18) | No approved-absence state exists to derive from | No — unblocked by the above |
| **Issue Reports resolution** | No screen only | **No** — `issue_reports_update` already exists |

The order follows from the table: Issue Reports triage is buildable **today** against
existing policies, Requests approval needs a design decision *and* a migration before any
UI, and Attendance's auto-excuse falls out of Requests approval for free. Academy-web now
has three student-facing submission flows (tasks, absence requests, issue reports) whose
staff-facing halves are all missing — students can put things into the system faster than
anyone can take them out.

## 8. Confirmed decisions

- **Attendance scope:** a User can only check in to sessions tied to Programs they're actively enrolled in — not a general, program-less check-in. Enforced at the database level via RLS (tested: enrolled succeeds, non-enrolled is blocked, Staff/Admin logging on someone's behalf bypasses the check since they're not self-checking-in).

- **Platform: both web and native.** Academy ships as a Next.js web app and a Flutter native app, both against the same Supabase backend. Native carries genuine offline support (Drift) for attendance check-in and push notifications for deadlines/announcements; web covers anyone who'd rather not install an app. This roughly doubles Academy's frontend build — accepted as a deliberate tradeoff, not a default.
- Holiday/Bootcamp participants get a performance view too, same as Interns/Students — not a smaller dashboard.
- Blog posting from Academy stays **Could** (later, not MVP) — confirmed it's fine to overlap with Site content on a longer timeline rather than shipping with v1.

## 9. Assumptions to confirm

*(none outstanding — see confirmed decisions above)*
