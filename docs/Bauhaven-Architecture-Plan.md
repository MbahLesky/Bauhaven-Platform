# Bauhaven Platform — Architecture Plan

## 1. Product summary

Bauhaven needs to manage interns, students, holiday-makers, and staff across courses/programs, tasks/projects, attendance, assets, finance, and public web content — plus keep its live public website (**www.bauhaven.com**) updated. Two earlier planning docs (module-based and role-based) cover the same ground with inconsistent naming (Course vs Program) and gaps (Announcements/Requests/Notifications/Invitation only in one doc). This plan reconciles both into one buildable structure.

**Decision:** build as **separate apps sharing one auth/user core**, not one monolith. The internal-facing apps (courses, tasks, finance, assets) are consolidated into a **single Admin app** since Admin/Manager/Staff cross all of these day-to-day — one login, one place, with permissions controlling what each sub-role sees inside it. **Admin and Academy each ship as two clients — web and native — against the same backend**; Site stays web-only.

## 2. App breakdown

| App | Owns | Who uses it | Clients |
|---|---|---|---|
| **Bauhaven Core** (not user-facing on its own) | Users, roles, permissions, announcements, notifications, requests, invitations, issue reports | Backend service every other app calls | — (backend only) |
| **Bauhaven Admin** | Courses/Programs, applications, enrollment, projects/tasks, submissions, feedback, attendance, finance, assets, **website content editor**, issue report resolution | Admin, Managers, Staff (Auditor, Internship Coordinator, Programme Manager, Mentor/Supervisor) | Web (Next.js) + native (Flutter) |
| **Bauhaven Academy** (portal) | Intern/student dashboard, task submissions, attendance submission, testimonies, issue reporting, profile | Interns, Students, Holiday-makers | Web (Next.js) + native (Flutter) |
| **Bauhaven Site** *(already live)* | Public pages, portfolio, blog, application intake | Public — existing site at www.bauhaven.com, not being rebuilt | Web (Next.js, unchanged) |

Rationale for this split:
- **Core** stays a shared backend (Supabase project) — every client authenticates against it and reads role/permission data from it. RLS enforces authorization once, centrally, so it isn't duplicated per client.
- **Admin** consolidates what would otherwise be three separate internal apps (course/program management, finance, assets) into one — a Programme Manager checking attendance and an Auditor checking transactions shouldn't need two logins and two tools. Permissions scope what each sub-role sees within it.
- **Academy** stays a separate app from Admin because it's a different user base entirely (interns/students, not staff) with different UI needs — and it should not carry any finance/asset access at all.
- **Web + native for both Admin and Academy:** covers both desk-based back-office work and mobile/on-site use (attendance check-in, field access, push notifications) without forcing one client to be a compromise for the other's use case. This roughly doubles frontend engineering effort per app — a deliberate tradeoff, not a free upgrade.
- **Site** already exists and is live. This plan does not rebuild it — the new work is a **content editor inside Bauhaven Admin** that manages what the live site displays (see Section 5).

## 3. Connectivity model

**Online-first, with offline tolerance only where it's actually needed:**
- Web clients (Admin, Academy): online-first — used with generally available connectivity.
- Native clients (Admin, Academy): same online-first default, but built on Drift (local reactive SQLite) so attendance check-in and other field actions can queue locally and sync when back online — genuine offline tolerance rather than the web clients' best-effort caching.
- Attendance check-in specifically: cache-and-queue **on the native clients**, since it's used at physical check-in points where wifi can be spotty.

  *(Corrected during Academy-web's Attendance build. This line previously read "cache-and-queue **regardless of client**", which contradicted the line directly above it — web clients get best-effort caching, native gets genuine queued writes via Drift. The two readings can't both hold, and "regardless of client" is the one that has to give: a web page cannot guarantee a queued write ever syncs. The tab closes, the browser evicts storage, and there is no durable background-sync primitive in this stack. For attendance specifically that gap is not academic — a student who is told "saved, will sync when you're online" and then isn't on the register has been actively misled about the one thing this screen exists to record. Academy-web therefore fails a check-in with a plain error and a retry, and says so on the card. Keeping the queue native-only is also what makes native's offline capability a real differentiator rather than a nominal one.)*
- Site: already live — whatever hosting it currently uses; the content editor adds a new integration point, not a new hosting decision.

## 4. Data model

Grouped by owning app. Durable defaults across all: UUID primary keys, `created_at`/`updated_at` in UTC, soft deletes on User/Program/Asset/FinanceRecord (history matters for audits), money as integer minor units + currency code.

**Core**
- `User` (identity only: name, email, phone, profile photo, `preferred_language`) — no single role field
- `UserRole` (user_id, role: admin/staff/intern/student/holiday_maker, staff sub_role: auditor/coordinator/programme_manager/mentor, status: active/inactive, `started_at`, `ended_at` nullable, optional link to `Program`/`Enrollment`) — one user can hold **multiple rows, concurrently or over time**: an intern who's also enrolled as a student on a different program, or a former intern who's now a Mentor. Permission checks look at *active* `UserRole` rows, not a single field on `User`.
- `Role` / `Permission` (role → allowed actions per app/module, so access changes don't need code deploys) — plus **individual overrides on top of the role default** (e.g. one specific Staff member granted Finance access, or one specific Student granted permission to create their own Tasks), since some grants are per-person, not per-role
- `Announcement`, `Notification`, `Invitation`
- `Request` (absence/unavailability request: requester_id, type, start_date, end_date, reason, status: pending/approved/rejected) + `RequestApproval` (request_id, approver_id, decision, decided_at) — one row per required approver, since quorum varies: User→1 Staff, Staff→1 Admin, **Admin→every other Admin (unanimous)**; approval marks the matching `Attendance` session as excused
- `IssueReport` (submitted by any user, category, status: open/in_progress/resolved, optionally linked to an `Asset` or `Program`) — this is what "Report" in the source docs meant: users flagging problems, not financial reporting

**Admin** *(single app, multiple modules)*
- *Courses/Programs:* `Program` (type: course | program, duration, fee, modules), `Application`, `Enrollment`, `Service` (name, description — lightweight catalog, no booking/payment in v1)
- *Tasks:* `Project`, `Task`, `Submission`, `Feedback`
- *Attendance:* `Attendance` (session-based, linked to User)
- *Finance:* `FinanceRecord` (transaction type, amount, currency, receipt ref) — analysis/summaries are computed views over this table, not a separate stored entity
- *Assets:* `Asset` (physical/digital, status: fine/needs_repair/retired, assigned_to User, nullable)
- *Content editor (new):* `Page`, `ContentBlock`, `PortfolioEntry` (links User + Program — "showcase this intern's work"), `Blog` (status: draft/pending/approved) — all bilingual: `title_en`/`title_fr`, `body_en`/`body_fr` per row, so EN/FR is a native field pair rather than a retrofit
- *Support:* review/resolve `IssueReport`s raised by any user

**Academy**
- `Testimony` (submitted by intern/student)
- Submits `IssueReport` (owned by Core, not duplicated here) — "report problems" from the source doc
- Reads its own `Enrollment`/`Task`/`Attendance`/`Submission` rows from Admin's tables, scoped to the logged-in user — doesn't duplicate that data.

**Site** *(existing, external)*
- No new tables. Reads `Page`/`ContentBlock`/`PortfolioEntry`/published `Blog` from Admin's Content module via a read-only API. Writes new `Application` rows back into Admin when someone applies publicly.

## 5. Storage, backend, and the website builder

**Supabase** for Core/Admin/Academy — Postgres, Auth, Storage, Realtime in one place, with Row-Level Security enforcing e.g. "Staff can only see their assigned students" at the database layer.

- Admin, Academy: **React + Tailwind**.
- **Website content editor:** www.bauhaven.com is custom-coded Next.js with no CMS, so the editor gets built — a module inside Admin where Staff/Admin edit `Page`/`ContentBlock`/`PortfolioEntry`/`Blog` rows in Supabase. This is a **headless CMS pattern**, and Next.js is actually the best-case target for it:
  - Content lives in Supabase Postgres (RLS: public read on published rows only, write restricted to Admin/Staff roles).
  - The Next.js site reads it server-side (Supabase server client in Server Components) rather than calling a separate public API — one less moving part.
  - Use **on-demand ISR**: when Staff hit "Publish" in the content editor, Admin calls a webhook on Site to revalidate the affected page. Confirmed hosted on **Vercel**, which supports this natively.
  - No changes needed to how www.bauhaven.com is currently hosted/deployed — this only adds a data source and a revalidation hook.

### The revalidation webhook contract

**`POST /api/revalidate`** on Site.

**Auth:** shared secret via header — `x-revalidate-secret: <secret>` — **not** a query string. An earlier draft of this contract put the secret in `?secret=...`, which is wrong: query strings land in server and proxy access logs, so a "secret" there isn't actually secret. Header only. The secret lives in each app's environment variables (Site's Vercel env, Admin's server-side env) — never in client-side code, since Admin's revalidation call happens from a Server Action, not the browser.

**Request body:**
```json
{ "paths": ["/portfolio", "/portfolio/a-booking-platform-for-a-local-tailor-shop"] }
```
Admin sends the specific path(s) affected by what was just published — the portfolio index plus the specific entry, not a blanket revalidate-everything call.

**Response:**
```json
// Success
{ "data": { "revalidated": ["/portfolio", "/portfolio/..."] } }
// Failure
{ "error": { "code": "invalid_secret" | "revalidation_failed", "message": "..." } }
```

**Implementation note (added during the Admin-web content editor build):** the contract above is implemented verbatim in `bauhaven-admin-web` as `src/lib/site-revalidate.ts` — header auth, both response shapes, `warn`-level logging, and the 2-attempt short backoff. Two things the build surfaced that the contract didn't cover:

- **Per-entry portfolio paths aren't reachable yet.** The request-body example shows `/portfolio/a-booking-platform-for-a-local-tailor-shop`, but `portfolio_entries` has **no `slug` column** — so Admin has nothing to build that path from, and a uuid-based guess would ask Site to revalidate a route that may not exist. Publishing an entry currently sends `["/portfolio"]` (the index), which is correct and complete for a Site that renders entries from it. **Adding `slug` to `portfolio_entries` is an M6 prerequisite** if Site gives each entry its own route.
- **A third outcome, "not configured".** With `SITE_REVALIDATE_URL`/`SITE_REVALIDATE_SECRET` unset, Admin publishes and reports that nothing was refreshed, rather than reporting a failure. An Admin instance running against no Site is a normal local-development state, and treating it as a failure trains people to ignore the warning that matters.
- **Slug→path mapping.** Admin maps a page's slug to `/<slug>`, special-casing `home` → `/`. That's the one rule Admin has to guess at; confirm it against Site's real route table at M6.

**Error handling — this call is best-effort, not transactional:** the content editor's "Publish" action commits the database write regardless of whether this webhook succeeds. A failed revalidation call is logged (`warn` level) and surfaced as a soft, non-blocking notice in Admin's UI ("Published — the live site may take a few minutes to catch up") rather than rolling back the publish or blocking the Staff member's workflow. Rationale: revalidation failing means a page is briefly stale, not that anything is broken or lost — treating it as fatal would hold real work hostage to a secondary system's uptime. A simple retry (2 attempts, short backoff) covers transient failures; anything beyond that just waits for the next publish or a manual re-trigger, since re-revalidating the same path twice is harmless (idempotent).

## 6. Auth strategy

Single Supabase Auth instance shared by Core, Admin, and Academy = **one login, works everywhere** — directly fixes the "previous apps not aligned" complaint. On login, each app fetches the user's *active* `UserRole` rows (not a single field) and shows only what those roles allow. If someone holds more than one active role — an intern also enrolled as a student, or a former intern now a Mentor — they get a lightweight **profile switcher** (e.g. "Continue as Intern" / "Continue as Mentor") rather than one app trying to merge both views into one screen. Phone/OTP as a login option is worth considering given intern/student populations may not all have reliable email. The public Site doesn't need accounts for browsing — only the application-submission form writes into Bauhaven's data.

### Auth as built (Admin-web, then Academy-web)

Both web apps now implement this section, and implement it **identically** — Academy's auth is a port of Admin's, not a re-derivation. Same middleware (session refresh + redirect), same Server Action with the same deliberately generic "Invalid email or password" (never distinguishing a wrong password from a missing account), same Zod schema in its own module rather than inside the `"use server"` file. That last point is a build-breaking constraint rather than a style preference: a schema exported from a `"use server"` file compiles fine but silently isn't the real schema by the time a client component imports it. One product having one login should mean one implementation of it, so a change to either app's auth belongs in both.

Two deliberate deviations, both recorded rather than absorbed:

- **"On login, each app fetches the user's active `UserRole` rows" is true of Admin, not yet of Academy.** Admin needs roles immediately — Finance access, Admin-only approvals, the Staff/Admin write gates — so it has `getCurrentUser` reading `user_roles`. Academy's screens are not role-gated yet: its nav is Home/Tasks/Attendance/Profile for everyone, and a role lookup with no consumer would be speculative code. Academy gains role-awareness when it gains the first thing that needs it, which is the profile switcher below.

- **The profile switcher is not built in either app.** It is a Must in the Core Feature Spec (#7) and the Academy Feature Spec (#2), and it sits in M3's gate in the Development Plan — correctly, since it needs more than an auth pass to be meaningful: a real notion of which role a session is currently *acting as*, somewhere to persist that choice, and screens whose content actually varies by it. Academy's wireframe shows the entry point ("Viewing as Intern ▾" on Home). Building it inside a basic auth pass would have produced a dropdown that changes nothing. Core's own spec already flags this ("worth a quick wireframe of the profile switcher before building it") — that wireframe is still the prerequisite.

**Phone/OTP login** remains unbuilt and unscoped; the note above says "worth considering", and nothing has decided it. Both apps are email + password today.

## 7. Roadmap

Shipping all modules together — phasing here is by **depth within each app**, not by which app comes first.

| Phase | Scope | Priority |
|---|---|---|
| **1 — MVP** | Core (users/roles/auth via `UserRole` supporting multiple/changing profiles per person, bilingual `preferred_language` on User); Admin — Programs/Enrollment, Tasks/Submissions, Attendance, Finance (record transactions), Assets (registry + assignment); Academy (dashboard, task submission, attendance, issue reporting, profile switcher if >1 active role); Content editor (Page/PortfolioEntry with EN/FR fields, publish → Next.js revalidation webhook) | Must |
| **2 — Quality of life** | Announcements/Notifications, Requests/Invitations, feedback/grading workflows, blog with approval flow, financial analysis dashboards, EN/FR language-switch UI across Admin/Academy/Site | Should |
| **3 — Growth (confirmed future scope)** | Payment integration, advanced analytics, testimonies workflow, refined asset access rules | Could |

## 8. Testing plan

- **Automated:** finance calculations, enrollment/duration logic, role/permission checks — where a silent bug costs money or exposes data.
- **Manual checklist:** attendance check-in under poor connectivity, cross-app login (does Staff access to Admin correctly restrict Finance modules from non-Auditor staff), asset assignment/status transitions, content editor → live site publish flow.
- **Docs shipped:** README per app, this plan, a shared "Core API contract," and — once the site's stack is confirmed — an integration doc for how content flows from Admin to www.bauhaven.com.

## 9. Risks and open questions

- **All-modules-at-once MVP is a large first release.** Admin alone bundles five modules — recommend building Core first (nothing else works without it), then Admin's modules in the priority order your team assigns.

**Resolved decisions** (kept here for traceability):
- `Report` = user-submitted issue/problem reports (Core's `IssueReport`), not financial reporting.
- Payment integration is confirmed future scope (Phase 3) — `FinanceRecord` doesn't need a provider reference yet.
- EN/FR bilingual support is in scope from Phase 1 (schema-level: `_en`/`_fr` fields on content, `preferred_language` on User); the language-switch UI itself lands in Phase 2.
- A person can hold multiple roles, concurrently or sequentially (intern → student, intern → mentor, etc.) — modeled as `UserRole` rows rather than a single field on `User`, decided from Phase 1 since retrofitting a single-role assumption later would touch every permission check in Admin and Academy.
- www.bauhaven.com is hosted on **Vercel** — on-demand ISR revalidation works natively via a standard API route + secret env var, no extra infrastructure needed.
- Some permissions are granted per-individual rather than per-role — e.g. Finance access for a specific Staff member, or Task-creation for a specific Student — so `Permission` supports overrides on top of the role default, not just role-wide toggles.
