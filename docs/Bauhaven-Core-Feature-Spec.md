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
| 1 | User CRUD (create/edit/archive) | Admin | Must | Soft delete, not hard delete |
| 2 | Assign/revoke `UserRole` (multi-role support) | Admin, Staff (scoped) | Must | The core of the multi-profile requirement |
| 3 | Role-based permission checks per app/module | All apps read this | Must | What Admin/Academy access control is built on |
| 4 | Login/session (email + password) | All | Must | Supabase Auth |
| 5 | Phone/OTP login | Users without reliable email | Should | Common for intern/student populations |
| 6 | Profile management (photo, language, contact) | All | Must | |
| 7 | Profile switcher (when a user has >1 active role) | Multi-role users | Must | Shared component, embedded inside Admin/Academy. **Not built in either app.** Both have working auth as of Academy-web's auth pass; the switcher was deliberately left out of it — see `Bauhaven-Architecture-Plan.md` §6, "Auth as built" |
| 8 | Invitations (send + accept) | Admin, Staff → invitee | Must | Drives onboarding |
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
- **Invitation flow:** assumed the invitee sets their own password via an emailed link (standard practice) rather than being issued one — confirm this matches intent.

## 8. Confirmed decisions

- Issue reports route to Staff **by category** (e.g. asset problems → Assets-permission staff), not all through Admin first.
- Course/program/asset access is **scoped per role** (tied to a specific Program/Asset via `UserRole`), not a platform-wide toggle.
- An approved absence Request **automatically marks** the matching `Attendance` session as excused, but Staff retain the ability to override/undo it if a mistake is caught.
- **Approval quorum depends on who's requesting:** a User's request needs one Staff approval; a Staff's request needs one Admin approval; an **Admin's own request needs approval from every other Admin** (unanimous, not just one) — this needs a `RequestApproval` join table (one row per required approver) rather than a single `approver_id` field on `Request`, since the Admin case can require more than one signer. **If there's only one Admin total, the request auto-approves** (zero other Admins required = quorum trivially met).

## 9. Assumptions to confirm

*(none outstanding — all resolved above)*
