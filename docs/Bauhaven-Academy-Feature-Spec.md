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
| 2 | Profile switcher (if >1 active role) | Multi-role users | Must | Shared component from Core. **Still not built** — third pass to leave it out, and the first to ship something in its place: Profile lists active roles **read-only**. Switching needs an "acting as" session concept and screens that vary by role; neither exists. The one named M3 gate item outstanding — see §7, "Profile" |
| 3 | Profile management (photo, language, contact) | All | Must | **Built, partly read-only** — language persists to `users.preferred_language`; contact details display but don't edit; no photo upload (no storage bucket). See §7, "Profile" |
| 4 | View enrolled Programs/courses | All | Must | |
| 5 | View assigned Tasks & deadlines | All | Must | |
| 6 | Create own Task/Project (if granted permission) | Permission-gated | Should | Gate confirmed in Admin's spec |
| 7 | Make Submission | All | Must | |
| 8 | View Feedback/grades on Submission | Intern, Student | Must | |
| 9 | Submit attendance (check-in) | All | Must | **Web: online-only**, plain error + retry on failure. Cache-and-queue is the *native* client's capability (Drift) — see `Bauhaven-Architecture-Plan.md` §3 and §8, "Attendance" |
| 10 | View attendance statistics | All | Must | |
| 11 | Submit absence/unavailability Request | All | Must | Entity owned by Core, submitted here. **Both halves built.** Submission here; approval in Admin-web at `/requests`, with the quorum rule and `008_request_approval_rls.sql` — see §7, "Requests" |
| 12 | View performance summary | All | Must | Confirmed to include Holiday-makers |
| 13 | Submit Testimony | Intern, Student, Holiday-maker | Should | **Submission built; no curation screen exists and `testimonies` has no UPDATE policy — see §7, "Testimonies"** |
| 14 | Report an issue | All | Must | **Both halves built.** Submission here; Staff triage in Admin-web at `/issue-reports` — a flat list with a category filter, no migration needed. See §7, "Issue reports" |
| 16 | Sign up, which files an application | Prospective applicants | Must | **Built** — `/signup` creates the account and the application together (`012_academy_signup_applications.sql`). Everything above stays behind an enrolment gate until an Admin approves; a pending applicant sees where their application stands, not empty screens. See §7, "Sign-up and the enrolment gate" |
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
  `using (true)`, so every authenticated user can read every session. This query genuinely
  has to filter by `program_id` itself. *(This bullet previously said "unlike `tasks` or
  `attendance_records`" — see the correction directly below. Sessions are the most
  unscoped policy, not the only one.)*

- **Corrected during the reconciliation audit: every attendance read now names its subject
  with `.eq("user_id", …)`.** The queries previously relied on RLS alone, with a comment
  asserting `attendance_records_select` scopes to `user_id = auth.uid()`. The policy is
  actually `user_id = auth.uid() **or auth_is_admin_or_staff()**`, and the comment quoted
  only the first arm.

  For a student that made no difference, which is why it survived review. For anyone holding
  a Staff or Admin role it returned **every student's records** — and that is an ordinary
  case, not an exotic one: one login serves the whole platform and a person can hold several
  roles concurrently (`Bauhaven-Architecture-Plan.md` §6), which is the entire premise of the
  profile switcher. The failure is not just "too many rows": `resolveRecordsBySession`
  partitions by session and documents that it expects **one** student's rows, so several
  students' records collapse to one arbitrary standing record per session. The attendance
  rate wasn't wide, it was wrong. `checkIn`'s duplicate check had the same shape and would
  have reported a classmate's row as "you're already checked in", blocking a real check-in.

  **This is scoping a personal view to its subject, not re-implementing authorization.** The
  policy is correct and stays the authority; the query was asking the wrong question. That's
  the same call `testimony-queries.ts` and `profile-queries.ts` had already made — and
  `Bauhaven-Coding-Standards.md`'s "don't duplicate permission logic in the client" is about
  deciding *who may*, which this doesn't touch. Regression test:
  "ignores a classmate's record for the same session".

  **Still open, deliberately:** `task-queries.ts`, `request-queries.ts` and
  `issue-report-queries.ts` have the identical shape and were left alone, because each
  states the opposite decision in its own comment rather than having overlooked it. Settling
  that convention across all four is a decision, not a cleanup — see the audit's findings.

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

**Two-sided gap — both halves now closed.** *(This section recorded a prediction while the
approval side was unbuilt. It is kept, corrected, because the prediction was wrong in a way
worth seeing: the auto-excuse went into the **write** path, not the read path.)*

1. ~~*This side* — no approval screen exists anywhere.~~ **Built** in Admin-web at
   `/requests`, on top of `008_request_approval_rls.sql`. The quorum rule is a pure function
   with unit tests (`src/lib/approval-quorum.ts`); `request_approvals` rows are created
   lazily on first view, since nothing in the schema routes a request to a named approver.
2. ~~*Admin-web's Attendance* — feature #18's auto-excuse is marked `TODO(requests)`.~~
   **Built, and no `TODO(requests)` remains in Admin-web** — the remaining mentions of that
   marker are all past-tense narration of how it was closed.

   **It landed in the write path, not the read path this section predicted.** Approving a
   request inserts real `excused` `attendance_records` rows, and creating a session marks
   anyone whose approved absence already covers that date — the second direction is
   load-bearing, because absences are normally approved *before* the session exists, so an
   approval-time-only implementation would have found nothing to mark in the common case.
   Writing rather than deriving means every client sees the same fact, it lands in the audit
   trail with a timestamp, and a Staff override stays an ordinary correction on the
   append-only chain. An `absent` mark is corrected; a `present` mark is never overridden —
   that contradiction is logged and reported to the approver instead. Full reasoning in
   `Bauhaven-Admin-Feature-Spec.md` §8, "Approvals & triage".

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

### Testimonies — decisions made while building the screen

These came out of implementing the "Share feedback" screen (feature #13) in
`bauhaven-academy-web`. **Submission only.**

- **One free-text field, matching the wireframe — not two language boxes.** `testimonies`
  has separate `content_en` and `content_fr` columns, but which one a student's words
  belong in is not a question to put to the student: `users.preferred_language`
  (`not null default 'en' check in ('en','fr')`) already answers it, and the Server Action
  reads it there. Showing both fields would have been the easy implementation and the wrong
  product — it asks someone to translate their own testimonial, which is a translator's job
  and not a condition of saying something nice about a program. The unused column stays
  **null**, never a copy of the other: duplicating would tell the public Site that the
  French text *is* the English translation, and English readers would be shown French as
  though it were theirs.

- **This required a migration, `007_testimonies_bilingual_content.sql`.** `content_en` was
  `text not null` while `content_fr` was nullable — an encoding of "every testimony is
  written in English and French is an optional translation". That's right for editorial
  content (`pages`, `portfolio_entries`, which Content Editor already treats that way) and
  wrong for a person's own words. Under the old constraint a French-speaking student — a
  value `preferred_language` explicitly allows, in a bilingual country — had two possible
  outcomes: their words stored in a column named for English, or a failed insert. The
  constraint now says "at least one language is present" via a table check, and
  `content_en` is nullable. Safe to apply: nothing reads `testimonies` yet, and no existing
  row can violate the new check.

- **This is a *content*-language decision and did not need next-intl.** Content language
  and interface language are different problems: the schema already models the first with
  `_en`/`_fr` columns and `users.preferred_language`, while the second needs the i18n
  library nobody has set up. This form's own labels are still hard-coded English. See the
  Project Brief's "Known open items" — **next-intl remains outstanding across both apps**,
  and this is the second feature to run into it.

- **`program_id` is filled server-side from the active enrollment.** A pull-quote on the
  public Site is about a program, and the student already said which one by enrolling —
  asking again would be asking a question the system can answer. Nullable, so a student
  between programs can still say something.

- **`status` is not sent.** It defaults to `'submitted'` (`001_initial_schema.sql` line 469
  — checked, not assumed) with a check constraint of submitted/published. Publishing is
  Admin/Staff curation, and — as with `requests` — **`testimonies` has no UPDATE policy at
  all**, so no row can reach `'published'` by any route today. The curation screen doesn't
  exist either.

- **The status labels avoid implying a verdict.** `submitted` renders as "Shared", not
  "Pending", and its badge is neutral rather than warning: a testimony isn't an application
  waiting on an answer, and one that never gets featured hasn't failed. `published` renders
  as "On the website", which is what the student actually cares about.

- **No consent gate, per the Project Brief's "Known open items".** Consent is deferred, not
  decided — the same call Content Editor made for `portfolio_entries`, and inventing an
  opt-in checkbox here would quietly decide it. What the screen *can* honestly say is the
  wireframe's own subtitle plus what the policies guarantee: Bauhaven may feature this, and
  nothing publishes automatically. Worth noting the deferral now bites harder: a student
  cannot withdraw a testimony, since `testimonies` has SELECT and INSERT and nothing else.
  The Project Brief item has been widened to name testimonies alongside portfolio entries.

- **This is the one Academy query that must filter by the caller itself.**
  `testimonies_select` is `user_id = auth.uid() or status = 'published' or
  auth_is_admin_or_staff()`, and that middle arm is **not scoped to the caller**. Trusting
  RLS the way the task, request and issue-report queries do would have made a screen headed
  "Your testimonies" list every published testimony in the company as though the student
  had written them. `attendance_sessions_select` being `using (true)` is the other
  unscoped policy; this is the more dangerous of the two, because these rows belong to
  identifiable other people.



### Profile — decisions made while building the screen

These came out of implementing the Profile screen in `bauhaven-academy-web`, the last
unbuilt screen in its wireframe.

- **Everything the wireframe shows is storable today; no migration was needed.** `users`
  already carries `name`, `email`, `phone`, `location`, `profile_photo_url` and
  `preferred_language` (`not null default 'en' check in ('en','fr')`), and `user_roles`
  carries `role`, `staff_sub_role`, `program_id` and `status`. The schema was checked before
  assuming, and it turned out to be ahead of the apps rather than behind them.

- **The language toggle is real, and it already has a consumer.** It writes
  `users.preferred_language`, which Academy's testimony form reads to decide whether a
  student's words go to `content_en` or `content_fr` — so flipping it changes where the
  next testimony is stored. It is **not** a visual-only placeholder.

- **What it does not do is translate the interface, and the screen says so.** next-intl has
  never been set up in either app; every label, button, error and empty state is a
  hard-coded English string. The screen reads "Your language is saved and used for anything
  you write. The app's own labels are still English only — translation is coming", because
  letting someone tap FR and conclude the app is broken is worse than admitting the gap.
  **The recommendation is that full next-intl setup becomes its own task next** rather than
  being deferred a fourth time — see the Project Brief's "Known open items" and the
  Development Plan's M3 close-out.

- **Contact details display but don't edit, deliberately.** The columns exist and
  `users_update_own` would allow the writes, but `email` and `phone` are also sign-in
  credentials, and `public.users` holds them separately from `auth.users`. Changing one
  without the other silently desynchronises an account from its login — worse than not
  offering the edit. It needs `supabase.auth.updateUser` plus a re-verification flow, which
  is its own piece of work. `location` alone would have been an edit control for one field
  of three. The wireframe's "Contact information ›" and "Edit profile photo ›" rows are
  corrected accordingly.

- **No photo upload, because there is nowhere to upload to.** `profile_photo_url` is a URL
  column and no Supabase Storage bucket is configured on this project. The screen renders a
  photo if a URL is ever set and falls back to initials, which is the normal case rather
  than the fallback — nothing in either app can currently produce a URL.

- **Roles are read-only, and this is the third deferral of the switcher.** Listing what
  someone *is* needs only a query; switching which role a session *acts as* needs somewhere
  to persist that choice and screens whose content varies by it. Neither exists, and a
  dropdown that changed nothing would be worse than a list that's honest about being a
  list. The sub-role is shown when there is one — "Mentor" is more useful than "Staff" —
  and `holiday_maker` renders as "Holiday participant", since a database identifier isn't a
  thing to show someone.

- **Sign-out moved here and the header stopgap is gone.** It sat in the app-shell header
  through the Auth pass, documented there as temporary until Profile existed. There is now
  one sign-out in the app rather than two that could drift. It's also rendered on Profile's
  **error** boundary, deliberately: this page is the only way out of a session, so someone
  signed into the wrong account behind a failing profile read would otherwise be stuck.

- **A missing `users` row is treated as a fault, not an empty state.** `handle_new_user`
  creates it on sign-up, so its absence means something is wrong — surfaced through
  `error.tsx` rather than rendered as a blank profile. A failed *roles* read is not fatal by
  contrast: the name, email and language toggle are all still true and useful without it.

### Sign-up and the enrolment gate

Academy had **no signup route and no gate** — two facts that only look serious together.
Every account had to be created by hand or by invitation, and any account that *did* exist
got the whole app on sight.

- **Signing up is applying.** `/signup` takes name, email, optional phone, programme,
  optional note and a password, then creates the account and files the application in one
  action. The programme picker offers real `programs` rows — Academy can read the actual
  catalogue, unlike the public website's marketing categories — so an approved application
  already knows the cohort to enrol on.

- **The gate is enrolment, not role.** `(app)/layout.tsx` looks for an active enrolment and
  otherwise renders where the application stands: being reviewed, passed the first review,
  approved-but-incomplete, declined, or no application on file. Empty Tasks and Attendance
  screens would have read as "this is broken" rather than "you're not approved yet", and
  the person has no way to tell those apart.

- **Approved but still gated is a real state, and it says so.** Approval writes three
  things — the status, the role, the enrolment — and nothing makes them atomic. If the
  last two don't land, the applicant is told the place hasn't finished setting up rather
  than being shown a "we're reviewing it" that is no longer true; the reviewer gets the
  matching warning on the Admin side against the row they just approved.

- **A decline keeps the account.** They can apply again for another programme or a later
  intake. `idx_applications_one_open_per_applicant` is partial over the open statuses
  precisely so that a decline reopens the door.

### Four open threads, all pointing at the same missing surface *(three now closed)*

Worth raising before Academy-web's remaining scope (Profile) gets built further
ahead of Admin-web. These are not three unrelated TODOs — they're one absent
**approvals/triage surface in Admin-web**, seen from three sides:

| Thread | Where it's blocked | Needs a migration? |
| --- | --- | --- |
| ~~**Requests approval**~~ **Built** | — | Done: `008_request_approval_rls.sql`, quorum as a pure function, approver rows created lazily on first view |
| ~~**Attendance auto-excuse**~~ **Built** | — | Done: real `excused` records written on approval *and* on session creation; an `absent` mark is corrected, a `present` one never overridden |
| ~~**Issue Reports resolution**~~ **Built** | — | Done: flat list with a category filter at `/issue-reports`, no migration needed as predicted |
| **Testimony curation** | No screen; and `testimonies` has no UPDATE policy | **Yes** — a one-line policy, no design question attached. **The one still open.** |

**Update — three of the four are built.** Admin-web's Approvals & triage work delivered
issue-report resolution, absence-request approval (with the quorum rule and
`008_request_approval_rls.sql`) and the attendance auto-excuse that fell out of it, in
that dependency order. **Testimony curation is the one that remains**, and it is still the
cheapest of the four: a single UPDATE policy on `testimonies` gated on
`auth_is_admin_or_staff()`, then a screen. It was left out of that pass deliberately —
curation is an editorial workflow feeding the public Site, not an approval queue, and it
sits behind the deferred consent question in the Project Brief's "Known open items", which
is worth settling in the same pass rather than before it.

## 8. Confirmed decisions

- **Attendance scope:** a User can only check in to sessions tied to Programs they're actively enrolled in — not a general, program-less check-in. Enforced at the database level via RLS (tested: enrolled succeeds, non-enrolled is blocked, Staff/Admin logging on someone's behalf bypasses the check since they're not self-checking-in).

- **Platform: both web and native.** Academy ships as a Next.js web app and a Flutter native app, both against the same Supabase backend. Native carries genuine offline support (Drift) for attendance check-in and push notifications for deadlines/announcements; web covers anyone who'd rather not install an app. This roughly doubles Academy's frontend build — accepted as a deliberate tradeoff, not a default.
- Holiday/Bootcamp participants get a performance view too, same as Interns/Students — not a smaller dashboard.
- Blog posting from Academy stays **Could** (later, not MVP) — confirmed it's fine to overlap with Site content on a longer timeline rather than shipping with v1.

## 9. Assumptions to confirm

*(none outstanding — see confirmed decisions above)*
