# Bauhaven Platform

Shared foundation for the unified Bauhaven ecosystem — architectural documentation, live database schema (`supabase/db.sql`), ordered SQL migrations (`supabase/migrations/0001`–`0037`), and privileged Supabase Edge Functions (`supabase/functions/`).

All active Bauhaven applications share a single Supabase backend project (`keyaahfksbfigcdbbuda`).

## Active Projects (5)

| Project | Stack | Role |
|---|---|---|
| **Bauhaven-Platform** | Supabase (PostgreSQL, Auth, RLS, Edge Functions) + Markdown Docs | Single source of truth for database migrations, Edge Functions, and documentation |
| **Bauhaven-Admin-Web** | Next.js 16 (App Router, TypeScript, Tailwind v4) | Admin & Staff web console (Programmes/Cohorts, Applications, Enrolment, Tasks, Attendance, Absence Requests, Issue Reports, Assets, Content, People/Roles, and lightweight Finance Income/Expense entry) |
| **Bauhaven-Academy-Web** | Next.js 16 (App Router, TypeScript, Tailwind v4) | Participant / Learner web portal (Dashboard, Tasks & Submissions, Attendance History, Absence Requests, Issue Reports, Testimony/Feedback, Profile) |
| **bauhaven_ft** | Flutter (Riverpod, GoRouter, Supabase) | Dedicated Finance Tracker mobile app (full accounting, approvals, budgets, invoices, loans, petty cash, reports). **Protected — do not modify** |
| **bauhaven-website** | Next.js 16 (App Router) | Public marketing website and admissions intake (`public.applications`, `public.contact_messages`, `public.website_reviews`) |

## Paused Projects (Reference Only)

The following repositories are paused (marked with `PAUSED.md`) and kept as reference only:
- `bauhaven-admin` (Flutter Admin app — superseded by `Bauhaven-Admin-Web`; its backend migrations `0001`–`0032` and Edge Functions now live here in `Bauhaven-Platform/supabase/`)
- `BauhavenDocs` (Legacy planning documents — consolidated into `Bauhaven-Platform/docs/`)
- `studio-bauhaven-website` (Standalone Sanity Studio — paused while core platform unifies)

## Repository Structure

```text
docs/                         # Platform architecture & feature specifications
supabase/
  db.sql                      # Full reference dump of the live unified database schema
  migrations/                 # Ordered, idempotent SQL migrations (0001 through 0037)
  functions/                  # Shared Supabase Edge Functions:
    accept-admin-invitation/  #   Activates a staff member's pending role invitation
    approve-application/      #   Approves an application, creates enrolment & invites user
    bootstrap-super-admin/    #   One-time super_admin bootstrap
    invite-administrator/     #   Invites staff or grants a scoped role assignment
    notify-task-assignment/   #   Emails participants when a task is assigned
    resend-invitation/        #   Resends an applicant's invitation email
  proposed/                   # Reference copies of additive migrations 03–08 (now in migrations/0033–0037)
  archive-prototype/          # Archived early prototype migrations (001–015) kept for historical reference
```

## Migration Sequence (`supabase/migrations/`)

- `0001`–`0008`: Core extensions, RBAC (`profiles`, `roles`, `permissions`, `role_permissions`), catalogue (`offerings`, `cohorts`), admissions (`applications`, `application_reviews`, `application_approvals`), `invitations`, `enrolments`, `audit_logs`.
- `0009`–`0017`: Governance v2 (`user_role_assignments`, `admin_invitations`, `staff_profiles`, `get_my_active_roles()`, `private.has_permission()`, `public.has_permission_for()`).
- `0018`–`0019`: Learning (`learning_projects`, `tasks`, `task_assignments`, `submissions`, `feedback`).
- `0020`–`0024`: Finance schema and RLS (`finance_payment_accounts`, `finance_income`, `finance_expenses`, `finance_expense_categories`, `finance_budgets`, `finance_invoices`, `finance_loans`, `finance_petty_cash_entries`, `finance_transaction_events`, `finance_log_event()`).
- `0025`–`0032`: Public application tracking-code triggers, admin invite RPCs, participant platform tables (`attendance_sessions`, `attendance_records`, `notifications`, `announcements`, `digital_resources`, `participant_feedback` view), and non-recursive RLS helpers.
- `0033_attendance_staff_access.sql`: Scoped staff RLS policies for `attendance_sessions` and `attendance_records`.
- `0034_absence_requests_and_issue_reports.sql`: `absence_requests`, `absence_request_approvals`, and `issue_reports` tables + quorum RLS policies.
- `0035_assets.sql`: `assets` inventory table + RLS policies.
- `0036_cms_staff_editing.sql`: Staff `cms.publish` update policies on `page_sections`, `projects`, `testimonials`, and learner policies on `website_reviews`.
- `0037_admin_account_and_role_management.sql`: Direct account creation (`admin_create_account`) and role assignment revocation (`admin_revoke_role_assignment`).
