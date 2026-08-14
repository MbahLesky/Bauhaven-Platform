# Bauhaven Core — Feature Specification

## 1. Problem & background

Core is the shared backend — and a small set of shared UI components — that every other Bauhaven app (Admin, Academy, and parts of Site) is built on: identity, roles, auth, notifications, announcements, invitations, and issue reports. It's not an app someone opens on its own. It exists so the platform has **one account, one login, one source of truth for "who is this person and what can they do"** — directly solving the fragmentation of the previous apps.

## 2. Users

- **Admin (Founders):** full control over users, roles, and platform-wide announcements.
- **Staff** (Auditor, Internship Coordinator, Programme Manager, Mentor/Supervisor): manage users/roles within their assigned scope, resolve issue reports, send scoped announcements.
- **User** (Intern, Student, Holiday-maker): holds one or more `UserRole` records, manages their own profile, reports issues, receives notifications.
- **Public:** no direct Core account — only touches Core via an invitation-acceptance link when they're being onboarded.

## 3. User stories

**Admin**
- As an Admin, I want to create/edit/archive user accounts so I can manage platform access. *(Archiving is a soft delete — disables login, keeps history.)*
- As an Admin, I want to assign or revoke roles for any user so access matches their current real-world role(s), including holding more than one at once.
- As an Admin, I want to scope a user's role to specific courses/programs/assets so access isn't platform-wide by default.
- As an Admin, I want to post platform-wide or role-scoped announcements.

**Staff**
- As Staff (with permission), I want to invite new interns/students so they can self-onboard.
- As Staff, I want to view and resolve issue reports relevant to my area so problems get tracked to closure, not lost in chat.
- As Staff, I want to send announcements scoped to the group I manage.

**User (Intern/Student/Holiday-maker)**
- As a User, I want to log in once and see all my active roles so I can switch between them (e.g. "Intern" vs "Student" view) if I hold more than one.
- As a User, I want to update my profile (photo, preferred language, contact info).
- As a User, I want to report a problem so staff can address it.
- As a User, I want to submit an absence/unavailability request so my time away is recorded and doesn't count against my attendance without explanation.
- As a User, I want to receive notifications about deadlines, approvals, and announcements.
- As a User, I want to accept an invitation link and set my own password to activate my account.

**Staff (additional)**
- As Staff, I want to approve or reject absence requests from the Users I supervise, so attendance records reflect excused vs unexcused absences.
- As Staff, I want to submit my own absence/unavailability request to Admin.

**Admin (additional)**
- As an Admin, I want to approve or reject absence requests from Staff.

## 4. Feature list

| # | Feature | User(s) | Priority | Notes |
|---|---|---|---|---|
| 1 | User CRUD (create/edit/archive) | Admin | Must | Soft delete, not hard delete. **Built** — Admin-web's People screen (`/users`). Accounts are *created* by invitation rather than by an Admin typing a password, so "create" here means invite |
| 2 | Assign/revoke `UserRole` (multi-role support) | Admin | Must | **Built** — People screen. Admin only, matching `user_roles_write`; Staff see the directory read-only. Revoking deactivates rather than deletes, since `user_roles` records what someone *has been* |
| 3 | Role-based permission checks per app/module | All apps read this | Must | What Admin/Academy access control is built on |
| 4 | Login/session (email + password) | All | Must | Supabase Auth |
| 5 | Phone/OTP login | Users without reliable email | Should | Common for intern/student populations |
| 6 | Profile management (photo, language, contact) | All | Must | |
| 7 | Profile switcher (when a user has >1 active role) | Multi-role users | Must | Shared component, embedded inside Admin/Academy. **Not built in either app.** Both have working auth as of Academy-web's auth pass; the switcher was deliberately left out of it — see `Bauhaven-Architecture-Plan.md` §6, "Auth as built" |
| 8 | Invitations (send + accept) | Admin, Staff → invitee | Must | **Built** — needed `009_invitations_and_onboarding.sql`. Send from Admin-web's People screen; accept at `/invite/[token]` in **both** apps. Nothing is emailed (no provider configured) — the link is handed to the sender. See §8, "Onboarding as built" |
| 8b | Self-signup that doubles as an application | Anyone → Admin | Must | **Built** — needed `012_academy_signup_applications.sql`. Academy's `/signup` creates the account and files the application in one step; approving in Admin grants the role and enrols. No invitation is issued on this path — the account already exists. See §10 |
| 9 | Announcements (post, scoped to role/group) | Admin, Staff → all | Should | |
| 10 | Notifications (system-generated: deadlines, approvals) | All | Should | |
| 11 | Requests: absence/unavailability, with role-based approval (User→1 Staff, Staff→1 Admin, Admin→all other Admins) | All | Must | Approved request auto-marks the matching Attendance session as excused; Staff can override |
| 12 | Issue reporting (submit/track/resolve) | Users submit; Staff/Admin resolve | Must | This is the "Report" feature from the source docs |
| 13 | Audit log of role/permission changes | Admin | Could | Accountability, not MVP-critical |

## 5. Out of scope — v1

- Payment/billing (confirmed future scope, lives in Admin's Finance module regardless).
- Per-field permission editing (role → module access is enough for v1).
- SMS-based password reset (email reset only; phone/OTP *login* is separately a Should).

## 6. Success criteria

- 100% of Admin/Academy logins go through Core — zero leftover separate accounts from the old apps, by launch.
- Granting/revoking a role takes effect without a support ticket or manual database edit.
- Issue reports get a first response within an agreed SLA (e.g. 48h) once Staff adopt the resolution flow.

## 7. Constraints, risks & open questions

- **Multi-role switching adds UI complexity** to both Admin and Academy — worth a quick wireframe of the profile switcher before building it.
- ~~**Invitation flow:** assumed the invitee sets their own password via an emailed link.~~ **Resolved, with one deviation worth knowing.** The invitee does set their own password — nobody, including the Admin who invited them, ever sees or chooses it. What is *not* emailed is the link itself: no mail provider is configured, so it's handed to whoever created the invitation to send however they actually reach the person. See §9.


## 8. Confirmed decisions

- Issue reports route to Staff **by category** (e.g. asset problems → Assets-permission staff), not all through Admin first. *(**The schema does not implement this, and the wording overstates what exists.** Confirmed twice: once while building Academy's submission screen, again while building Admin's triage screen. "category" appears in exactly two places in the whole schema — the `issue_reports.category` column (`text not null default 'general'`, **no check constraint**) and the index `idx_issue_reports_status_category`. No per-category staff assignment table exists, and nothing links a category to `user_roles.staff_sub_role` or to a permission. `issue_reports_select` and `issue_reports_update` both gate on plain `auth_is_admin_or_staff()` with **no category arm**, so every Staff member and every Admin can read and resolve every report. **Admin-web's `/issue-reports` is therefore a flat list with category as a filter**, which is what the index is for. Real routing would need a category→staff mapping table or a category arm in the policies; neither exists, and neither was built speculatively.)*
- Course/program/asset access is **scoped per role** (tied to a specific Program/Asset via `UserRole`), not a platform-wide toggle.
- An approved absence Request **automatically marks** the matching `Attendance` session as excused, but Staff retain the ability to override/undo it if a mistake is caught. *(**Built**, in Admin-web, and both halves of that sentence hold. The excuse is a real `attendance_records` row, so a Staff override is an ordinary correction on the append-only chain and wins because it supersedes. Two things this line didn't anticipate, decided while building: it runs **from both directions** — on approval for sessions that exist, and on session creation for absences approved earlier, since requests are normally approved before the session is made — and a student already marked **present** is never overridden. That last case is a contradiction between two true-looking records; it is logged and reported to the approver rather than resolved automatically. See the Admin Feature Spec §8, "Approvals & triage".)*
- **Approval quorum depends on who's requesting:** a User's request needs one Staff approval; a Staff's request needs one Admin approval; an **Admin's own request needs approval from every other Admin** (unanimous, not just one) — this needs a `RequestApproval` join table (one row per required approver) rather than a single `approver_id` field on `Request`, since the Admin case can require more than one signer. **If there's only one Admin total, the request auto-approves** (zero other Admins required = quorum trivially met). *(Status as built: **implemented in `bauhaven-admin-web` at `/requests`.** `008_request_approval_rls.sql` added the missing policies — `requests` had no UPDATE and `request_approvals` no INSERT, so nothing could leave `'pending'`. The rule itself is a pure function with unit tests (`src/lib/approval-quorum.ts`), including the single-Admin auto-approve, which falls out of the rule rather than being special-cased: zero other Admins is an empty unanimous set. Two things this spec left open were decided while building and are recorded in the Admin Feature Spec §8, "Approvals & triage": **which** Staff member approves a User's request — nothing routes, so approver rows are created **lazily on first view** and whoever opens the queue becomes the approver — and whether a rejection is decisive, which it is, in both quorum shapes.)*

## 9. Onboarding as built

Everything below came out of implementing invitations, user administration, the
application handoff and the first-admin bootstrap. Before that work, **there was no way to
create an account except by hand** — in either app, for anyone.

- **The gap was total, not partial.** Neither client had a signup route (Academy has one now — §10); `handle_new_user()`
  fills in `public.users` on sign-up but grants no role; and `user_roles_write` is
  `using (auth_is_admin())`, so a brand-new user cannot give themselves a role and only an
  existing Admin can give them one. Every account — the first Founder, every Staff member,
  every student — required a Supabase dashboard visit plus a direct SQL insert that
  bypasses RLS. `invitations` had been in `001_initial_schema.sql` from the start with a
  policy and no reader or writer.

- **No service-role key, deliberately.** Accepting runs as the invitee — anonymous first,
  then authenticated — through two `security definer` functions in `009`
  (`invitation_preview`, `redeem_invitation`), the same approach `auth_has_permission`
  already uses. A service-role key in an app's environment is a standing bypass of RLS on
  *every* table; adding one so a single flow can write two rows is a poor trade. The two
  functions can do exactly what they do and nothing else.

- **A real privilege escalation was closed on the way.** `invitations_admin_staff` was
  `for all using (auth_is_admin_or_staff())`, which let a **Staff member invite somebody as
  an admin** — granting through the invitation path a role they cannot grant directly via
  `user_roles_write`. `009` replaces it with policies that keep the two paths equally
  powerful: Staff may invite interns, students and holiday participants; creating Staff or
  Admins stays Admin's alone.

- **The role comes from the invitation, never from the accept form.** The invitee proves
  only that they hold the token *and* control the address it was issued to — `redeem_invitation`
  checks the signed-in account's email against the invitation's, which is what stops a
  forwarded link becoming somebody else's staff account. There is no email field on the
  accept screen for the same reason.

- **The first Admin cannot be invited, and that's correct.** Somebody has to insert the
  first `user_roles` row with a credential that bypasses RLS. `supabase/seed/001_first_admin.sql`
  makes that one unavoidable manual step a reviewed, repeatable, re-runnable script instead
  of tribal knowledge. Everything after it goes through the app.

- **Two lockout guards that RLS won't give you.** An Admin cannot remove their own Admin
  role, and cannot archive their own account. `user_roles_write` would allow both, at which
  point nobody can grant it back through the app and the fix is the seed script and a
  database credential.

- **Nothing is emailed, and the UI says so.** No mail provider is configured on this project
  and there is no notification delivery either, so the invitation link is handed to whoever
  created it, to send however they actually reach people — which for Bauhaven is as likely to
  be WhatsApp as email. Claiming an invitation had been "sent" when it was only written to a
  table is the same class of promise this codebase removed once already from Attendance.
  Wiring a provider later changes `inviteUser` and one component.

- **Email confirmation is handled rather than assumed off.** With it on, `signUp` returns a
  user but no session, so `redeem_invitation` — which needs `auth.uid()` — cannot run. The
  flow reports that honestly, leaves the invitation **unredeemed**, and finishes the job when
  the person reopens the same link once signed in. The account is created before the
  invitation is consumed on purpose: a failed redemption leaves a usable account with no role
  (recoverable by reopening the link) rather than a consumed invitation with no account
  (needs an Admin to reissue).

- **Approving an application now issues the invitation** — the "Application→Enrollment
  handoff" the Development Plan lists as deferred. `009` adds `program_id` and
  `application_id` to `invitations`, so redeeming enrols them in the program they applied to:
  application, account and enrolment in one chain rather than three manual steps. The role is
  `student`, because `applications` has no role field and nothing in the schema distinguishes
  an intern application from a student one; it's changeable in one click from People, which
  beats inventing a mapping from `programs.type` that would be wrong about as often as right.

- **`/invite/[token]` is reachable without a session in both apps**, and *with* one — unlike
  `/login`. An existing account can be invited to a second role (multi-role is the design),
  and someone who confirmed their email comes back to the same link. The token is the
  credential; middleware doesn't need to guess.

## 10. Self-signup as built

The second intake path, added after invitations. Someone can now create their own Academy
account, and doing so **is** applying — the account and the application are written
together, and an Admin approving the application is what turns a dormant account into a
usable one.

- **Two intake paths, one queue.** The public website's form still files an anonymous
  application with no account behind it; Academy's `/signup` files one carrying
  `applicant_id`. Both land in the same Applications screen with the same statuses and the
  same buttons — only the last step of approval differs, and `applicant_id` is what selects
  it. Keeping both was a recorded decision: the website is where most applicants first meet
  Bauhaven, and requiring an account before applying would lose them.

- **Approval branches on `applicant_id`.** An anonymous application still earns an
  invitation. An Academy sign-up gets the `student` role and the enrolment written directly,
  because there is nobody to invite — issuing an invitation to an address that already has
  an account produces a token that can never be redeemed, which is exactly the failure
  `inviteApprovedApplicant` already refuses to create.

- **Academy has a gate now; before this it had none.** Any signed-in account got the whole
  app, so a pending applicant would have seen Tasks, Attendance and Requests, all empty.
  Empty screens read as "this is broken", not "you're not approved yet", and the person
  can't tell which. `(app)/layout.tsx` checks for an enrolment and otherwise shows where the
  application stands.

- **Four pending states, not one.** `submitted`, `confirmed`, `approved` and *no application
  at all* say genuinely different things and are not collapsed into a single "pending"
  message. `approved` while still behind the gate means the role grant or the enrolment
  didn't land — approval writes three things and nothing makes them atomic — so that screen
  says so rather than leaving a now-false "we're reviewing it" up. The same failure is
  reported to the reviewer on the Admin side, against the row they just approved.

- **A declined application keeps the account.** Recorded decision. They can apply again for
  another programme or a later intake without starting from nothing, and the declined
  screen says that plainly rather than dressing up the outcome.

- **One open application per account**, enforced by a partial unique index rather than by
  the form — `idx_applications_one_open_per_applicant` covers `status in ('submitted',
  'confirmed')` only, so re-applying after a decline is allowed and anonymous applications
  are unaffected. Checking in the action instead would leave the double-submit race open.

- **`applications_select` gained an own-row arm.** It was Admin/Staff only, which meant an
  applicant could not read the application they had just filed — the pending screen would
  have had nothing to show. The new arm is `applicant_id = auth.uid()`, so it exposes their
  own row and nothing else.

- **`applicant_id` comes from the new session, never the form.** `signUpAndApply` reads it
  from the `signUp` result. An application naming somebody else's account wouldn't be
  escalation — approving it would grant the role to *them* — but it isn't a state the app
  should be able to produce.

- **The account is created before the application, on purpose.** A failed application leaves
  a usable account they can apply from again; the reverse — an application pointing at an
  account that doesn't exist — is not recoverable by them at all. Same ordering, and the
  same reasoning, as the invitation-acceptance flow.

- **Email confirmation is on.** With it on, `signUp` returns a user but no session. The
  application is still filed and the outcome is reported as "check your email" rather than
  as a failure, because nothing has actually gone wrong: the only thing outstanding is a
  link Supabase has already sent.

## 11. Assumptions to confirm

*(none outstanding — all resolved above)*
