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
- As Admin/Staff, I want to create and manage Projects/Tasks with deadlines and assign them to users.
- As a Student **with permission granted**, I want to create my own Task/Project to track independent work, not just assigned work.
- As Admin, I want to approve a Project.
- As the creator of a Task (Admin/Staff/Student), I want to delete it.
- As Admin/Staff, I want to give Feedback on a submission, scoped to students assigned to me.

**Attendance**
- As Admin/Staff, I want to create attendance sessions and track who attended. *(An approved absence Request from Core auto-marks the session excused.)*

**Finance**
- As Admin, I want to grant Finance access to a specific Staff member (typically an Auditor) so they can work with transactions — access isn't automatic just from holding that job title.
- As Admin/Staff (with Finance access), I want to create a Finance Record (log a transaction).
- As Admin, I want to approve/confirm a Finance Record before it's final.
- As Admin, I want to manage and view all Finance Records.
- As Admin, I want to see financial analysis (a computed summary, not a stored table) to gauge Bauhaven's monthly health.

**Assets**
- As Admin/Staff, I want to create/manage an Asset (physical or digital) and track its status.
- As Admin/Staff, I want to assign an Asset to a specific user.

**Website content editor**
- As Admin/Staff, I want to edit Page/ContentBlock content (EN/FR) so the public site stays current without a developer.
- As Admin/Staff/User, I want to add a Blog post — only Admin/Staff can approve it before it's public.
- As Admin/Staff, I want to publish a PortfolioEntry showcasing an intern/student's work, linked to their profile and Program.

**Issue reports** *(entity owned by Core, actioned here)*
- As Admin/Staff, I want to view and resolve IssueReports routed to my scope.

## 4. Feature list

| # | Feature | User(s) | Priority | Notes |
|---|---|---|---|---|
| 1 | Create/manage Program (course or program type) | Admin, Staff | Must | |
| 2 | Delete Program | Admin only | Must | RLS policy `programs_delete` exists and stays. **No delete UI in Admin-web v1** — retiring a program is an archive (see §8) |
| 3 | Assign/block Program access per user | Admin, Staff | Must | Ties to scoped `UserRole` access model |
| 4 | Set duration/module count per user (manual or auto by package) | Admin, Staff | Should | Auto-by-package needs a defined pricing model first |
| 5 | Grade student on Program | Admin, Staff | Must | |
| 6 | Add/manage Services (catalog) | Admin, Staff | Should | Light scope for v1 — name/description only |
| 7 | Submit Application (public entry point) | Public via Site | Must | Writes into Admin |
| 8 | Confirm Application | Admin, Staff | Must | |
| 9 | Approve Application | Admin only | Must | |
| 10 | Decline Application | Admin, Staff | Must | |
| 11 | Manage Enrollment | Admin only | Must | |
| 12 | Track Enrollment (read-only) | Staff | Must | |
| 13 | Create/manage Task & Project, assign with deadlines | Admin, Staff, Student (if granted) | Must | Student creation is permission-gated per person, not open to all students |
| 14 | Approve Project | Admin only | Should | |
| 15 | Delete Task/Project | Creator | Must | |
| 16 | Submission | Admin, Staff, Student | Must | |
| 17 | Feedback on submission | Admin, Staff (scoped) | Must | |
| 18 | Attendance sessions: create & track | Admin, Staff | Must | Auto-excuse via approved Request (Core) |
| 19 | Grant Finance access to a specific Staff member | Admin only | Must | Access is individually granted, not automatic by sub-role |
| 20 | Finance Record: create | Admin, Staff (with Finance access) | Must | |
| 21 | Finance Record: approve/confirm | Admin only | Must | |
| 22 | Finance Record: manage & view all | Admin only | Must | |
| 23 | Financial analysis (computed summary) | Admin | Should | Not a stored entity — dashboard/report view |
| 24 | Asset: create/manage, set status | Admin, Staff | Must | |
| 25 | Asset: assign to user | Admin, Staff | Must | |
| 26 | Content editor: Page/ContentBlock (EN/FR) | Admin, Staff | Must | Publish triggers Next.js revalidation |
| 27 | Blog: add post | Admin, Staff, User | Should | |
| 28 | Blog: approve post | Admin, Staff | Should | |
| 29 | PortfolioEntry: publish, linked to User + Program | Admin, Staff | Should | |
| 30 | Resolve IssueReport (routed by category) | Admin, Staff (scoped) | Must | Actioned here, entity owned by Core |

## 5. Out of scope — v1

- Payment/booking flow for Services (catalog only).
- Automatic package-based duration/module assignment (manual entry is enough until packages are formally defined).
- Public-facing Service browsing/purchase (Site can display info; buying is future).

## 6. Success criteria

- Every module (Courses, Applications, Tasks, Attendance, Finance, Assets, Content) is usable by Admin end-to-end without touching the old apps.
- Staff only ever see data scoped to their assignment — verified via a permission audit with zero cross-scope leaks in testing.
- An Application can go from public submission to enrolled Student without manual database work.

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
