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
| 11 | Submit absence/unavailability Request | All | Must | Entity owned by Core, submitted here |
| 12 | View performance summary | All | Must | Confirmed to include Holiday-makers |
| 13 | Submit Testimony | Intern, Student, Holiday-maker | Should | |
| 14 | Report an issue | All | Must | |
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

## 8. Confirmed decisions

- **Attendance scope:** a User can only check in to sessions tied to Programs they're actively enrolled in — not a general, program-less check-in. Enforced at the database level via RLS (tested: enrolled succeeds, non-enrolled is blocked, Staff/Admin logging on someone's behalf bypasses the check since they're not self-checking-in).

- **Platform: both web and native.** Academy ships as a Next.js web app and a Flutter native app, both against the same Supabase backend. Native carries genuine offline support (Drift) for attendance check-in and push notifications for deadlines/announcements; web covers anyone who'd rather not install an app. This roughly doubles Academy's frontend build — accepted as a deliberate tradeoff, not a default.
- Holiday/Bootcamp participants get a performance view too, same as Interns/Students — not a smaller dashboard.
- Blog posting from Academy stays **Could** (later, not MVP) — confirmed it's fine to overlap with Site content on a longer timeline rather than shipping with v1.

## 9. Assumptions to confirm

*(none outstanding — see confirmed decisions above)*
