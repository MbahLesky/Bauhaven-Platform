# Bauhaven Platform — Attendance, Finance, Onboarding & User Linking Implementation Guide

| Field | Value |
|---|---|
| Document Code | `BAU-ARCH-003` |
| Version | 1.0 |
| Date | 29 October 2026 |
| Target Repositories | `Bauhaven-Platform`, `Bauhaven-Admin-Web`, `Bauhaven-Academy-Web`, `bauhaven-admin`, `bauhaven-hub2`, `bauhaven_ft` |
| Migrations Covered | `0048` through `0053` |
| Status | Authoritative Implementation Documentation |

---

## 1. Executive Summary

This document records the architecture, database schema changes, and application-level implementations delivered to address three core operational requirements:

1. **Seamless Onboarding, Identity, & Account Lifecycle Management**
   - Corrected password reset and email confirmation redirects to route to the correct origin portal (`admin` vs `hub`).
   - Replaced automatic dummy password generation with an invitation-token activation flow where users securely set their own passwords.
   - Resolved the `null value in column "u_code" of relation "profiles"` constraint violation via automatic generation triggers.
   - Enabled Super Admin account deletion with cascade handling across Supabase Auth and application profile records.

2. **Flexible Attendance Engine & Multi-Day Recurrence**
   - Enabled admins to schedule recurring attendance sessions across multiple days of the week (e.g., Tuesdays, Wednesdays, and Fridays 9:00 AM – 2:00 PM) repeated for a month or up to a specific date.
   - Added audience targeting: attendance sessions can now be targeted either to entire cohorts or to specific individual user profiles (including learners, staff, and administrators).

3. **User-Linked Financial Records & Tuition Coverage Expiration Tracking**
   - Linked financial transactions directly to user profiles (`profiles`) and enrolments (`enrolments`), bridging the finance ledger with student progress.
   - Created the enhanced `finance_participant_balances` SQL view and configured Row-Level Security (RLS) so learners can view their own financial records.
   - Implemented a fractional month coverage calculation on the learner Hub (`Bauhaven-Academy-Web` and `bauhaven-hub2`). For example, if a monthly tuition of 20,000 XAF is partially paid with 15,000 XAF (75%), the dashboard tracks elapsed time through the covered period, turning red and 100% full at the end of the 3rd week with a callout to complete payment.
   - Added visual progress indicators and remaining balance pills (`5,000 XAF left` / `Paid`) beside enrollment names across both admin interfaces (`Bauhaven-Admin-Web` and `bauhaven-admin` Flutter app).

---

## 2. Onboarding, Identity & User Lifecycle

### 2.1 Password Reset and Email Redirect Disambiguation
**Issue:** When users requested a password reset or clicked confirmation links, the default redirect URL (`hub.bauhaven.com`) intercepted administrators, or admin reset links routed learners to the admin application.

**Resolution:**
- Configured discrete, application-specific callback and reset endpoints:
  - Admin Web: `/reset-password` and `/set-password`
  - Academy Web (Hub): `/reset-password` and `/set-password`
  - Mobile Apps: Deep-link URL schemes (`bauhaven-admin://auth/callback`, `bauhaven-hub://auth/callback`)
- In Server Actions and authentication services, redirect parameters now explicitly pass the originating application's domain rather than relying solely on the default project redirect URL.

### 2.2 Activation Without Dummy Passwords
**Issue:** Applications approved by administrators previously attempted to pre-generate user credentials with synthetic passwords, causing friction and confusion during onboarding.

**Resolution:**
- Implemented an invitation-driven onboarding model (migration `0048_learner_invitations_and_enrolments.sql`).
- Upon application approval or manual admin invitation:
  1. An invitation record is stored with an activation token, target programme, and cohort.
  2. The invitee receives an invitation email containing an activation link.
  3. The invitee opens the link, defines their own password, and activates their profile.
  4. The account is assigned the appropriate role (`intern`, `student`, `bootcamp_participant`, or staff role) and automatically linked to the designated enrolment.

### 2.3 `u_code` Automatic Generation
**Issue:** Direct user creation from the Admin portal failed with `null value in column "u_code" of relation "profiles" violates not-null constraint`.

**Resolution:**
- Applied migration `0051_fix_profiles_u_code_and_admin_create_account.sql`.
- Added a sequence and trigger function on `public.profiles`:
  ```sql
  create sequence if not exists public.seq_user_u_code start 1001;

  create or replace function public.trg_assign_profile_u_code()
  returns trigger as $$
  begin
    if new.u_code is null or trim(new.u_code) = '' then
      new.u_code := 'BH-' || to_char(current_date, 'YY') || '-' || lpad(nextval('public.seq_user_u_code')::text, 4, '0');
    end if;
    return new;
  end;
  $$ language plpgsql;
  ```
- Any insert into `profiles` lacking an explicit `u_code` now automatically generates a unique identifier (e.g. `BH-26-1001`).

### 2.4 Super Admin User Deletion
**Resolution:**
- Applied migrations `0049_fix_admin_delete_and_role_management.sql` and `0050`.
- Super Admins can permanently delete accounts via secure RPC (`admin_delete_user`), which cleans up related profile references, role assignments, and triggers Supabase Auth deletion safely without violating relational foreign keys.

---

## 3. Flexible Attendance Engine

### 3.1 Schema Upgrades (`0052_flexible_attendance_and_recurrence.sql`)
The `attendance_sessions` and `attendance_roster` tables were extended to support recurring multi-day schedules and non-cohort audience targeting:

```sql
alter table public.attendance_sessions
  add column if not exists recurrence_rule text,
  add column if not exists days_of_week int[],
  add column if not exists repeat_until date,
  add column if not exists audience_type text not null default 'cohort'
    check (audience_type in ('cohort', 'individuals'));

create table if not exists public.attendance_roster (
  id uuid primary key default gen_random_uuid(),
  session_id uuid not null references public.attendance_sessions(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint uq_attendance_roster_session_profile unique (session_id, profile_id)
);
```

### 3.2 Multi-Day Recurrence Patterns
Admins can define a recurrence pattern:
- **Selected Days of Week:** Array of integer days (`[1, 2, 4]` for Monday, Tuesday, Thursday or `[2, 3, 5]` for Tuesday, Wednesday, Friday).
- **Time Window:** Daily start and end times (e.g., 09:00 to 14:00).
- **End Date:** Specific date or repeated for 1, 2, or 3 months.
- When generating recurring sessions, the system iterates through each date in the window matching the specified days of the week, generating discrete attendance sessions with the same metadata and audience configuration.

### 3.3 Audience Targeting: Cohorts vs Individuals
- **Cohort Mode:** Retains existing cohort scoping (`cohort_id`). All active enrolments in that cohort are automatically rostered.
- **Individual Mode:** Allows selecting specific users from the organisation—including interns, students, mentors, tutors, staff members, and administrators. Roster entries are written to `attendance_roster`.

---

## 4. User-Linked Finance & Tuition Coverage

### 4.1 Schema Upgrades (`0053_link_finance_to_users_and_progress_coverage.sql`)
1. **Participant Linking:** Added `profile_id` to `finance_legacy_participants` to map legacy/offline participant records to Supabase user profiles:
   ```sql
   alter table public.finance_legacy_participants
     add column if not exists profile_id uuid references public.profiles(id) on delete set null;
   ```
2. **Transaction Linking:** Added user and enrolment foreign keys to `finance_income`:
   ```sql
   alter table public.finance_income
     add column if not exists payer_profile_id uuid references public.profiles(id) on delete set null,
     add column if not exists enrolment_id uuid references public.enrolments(id) on delete set null,
     add column if not exists legacy_participant_id uuid references public.finance_legacy_participants(id) on delete set null,
     add column if not exists period_start date,
     add column if not exists period_end date;
   ```
3. **Participant Charges:** Added coverage windows to `finance_participant_charges`:
   ```sql
   alter table public.finance_participant_charges
     add column if not exists period_start date,
     add column if not exists period_end date;
   ```
4. **Row-Level Security for Learners:**
   Configured RLS policies allowing authenticated users to select charges and income where `payer_profile_id = auth.uid()` or `profile_id = auth.uid()`.

### 4.2 Aggregated Balance View (`finance_participant_balances`)
The view aggregates active charges and approved income, calculating outstanding balances and percentage paid:
```sql
create or replace view public.finance_participant_balances as
with charge_totals as (
  select
    c.profile_id,
    c.legacy_participant_id,
    c.enrolment_id,
    c.currency,
    coalesce(sum(c.amount), 0) as total_charged
  from public.finance_participant_charges c
  where c.status = 'active'
  group by c.profile_id, c.legacy_participant_id, c.enrolment_id, c.currency
),
payment_totals as (
  select
    coalesce(i.payer_profile_id, lp.profile_id) as profile_id,
    i.legacy_participant_id,
    i.enrolment_id,
    i.currency,
    coalesce(sum(i.amount), 0) as total_paid
  from public.finance_income i
  left join public.finance_legacy_participants lp on lp.id = i.legacy_participant_id
  where i.approval_status in ('approved', 'auto_approved')
  group by coalesce(i.payer_profile_id, lp.profile_id), i.legacy_participant_id, i.enrolment_id, i.currency
)
select
  coalesce(ct.profile_id, pt.profile_id) as profile_id,
  coalesce(ct.legacy_participant_id, pt.legacy_participant_id) as legacy_participant_id,
  coalesce(ct.enrolment_id, pt.enrolment_id) as enrolment_id,
  coalesce(ct.currency, pt.currency, 'XAF') as currency,
  coalesce(ct.total_charged, 0) as total_charged,
  coalesce(pt.total_paid, 0) as total_paid,
  greatest(0, coalesce(ct.total_charged, 0) - coalesce(pt.total_paid, 0)) as outstanding_balance,
  case
    when coalesce(ct.total_charged, 0) = 0 and coalesce(pt.total_paid, 0) > 0 then 100
    when coalesce(ct.total_charged, 0) = 0 then 0
    else round((coalesce(pt.total_paid, 0) / ct.total_charged) * 100, 2)
  end as percent_paid
from charge_totals ct
full outer join payment_totals pt
  on (ct.profile_id is not distinct from pt.profile_id
      and ct.legacy_participant_id is not distinct from pt.legacy_participant_id
      and ct.enrolment_id is not distinct from pt.enrolment_id
      and ct.currency = pt.currency);
```

### 4.3 Learner Dashboard: Tuition Coverage & Expiration Math
When a student pays an amount less than their full fee (e.g. 15,000 XAF of 20,000 XAF due for a 30-day monthly cycle):
1. **Coverage Ratio Calculation:**
   $$\text{Coverage Ratio} = \min\left(1.0, \frac{\text{Amount Paid}}{\text{Amount Due}}\right) = \frac{15,000}{20,000} = 0.75 \text{ (75\%)}$$
2. **Effective Covered Days:**
   $$\text{Covered Days} = \text{Total Cycle Days} \times \text{Coverage Ratio} = 30 \times 0.75 = 22.5 \text{ days (approx. 3 weeks)}$$
3. **Expiration Date:**
   $$\text{Coverage Expiration} = \text{Period Start} + \text{Covered Days}$$
4. **Time-Elapsed Progress:**
   - The dashboard progress bar tracks the passage of time relative to the covered window:
     $$\text{Progress} = \frac{\text{Current Date} - \text{Period Start}}{\text{Covered Days}}$$
   - **Active State (Green):** Within the first 75% of the covered window.
   - **Expiring Soon State (Amber):** Within 3 days of covered period expiration.
   - **Expired State (Red & 100% Full):** Once the current date passes the covered window (e.g. at the end of week 3), the progress bar renders 100% full and red, displaying an urgent callout: *"Your tuition coverage has expired. Please complete your outstanding balance of 5,000 XAF to remain active."*

### 4.4 Admin Dashboard: Payment Status Beside Enrollment Name
In both Admin Web (`EnrollmentsTable.tsx`) and the Flutter Admin app (`enrollment_screen.dart`):
- Beside each participant's name, a compact badge is rendered:
  - If outstanding balance is 0: Green badge reading **Paid**.
  - If balance is outstanding: A mini progress bar showing percentage paid, accompanied by text: e.g. **5,000 XAF left**.
  - Color-coding: Green (100% paid), Amber (>50% paid), Red (<50% paid).
  - Detailed tuition amounts (`15,000 / 20,000 XAF (75%)`) appear in the row/card metadata.

---

## 5. Version Matrix Across Platform Apps

| Application | Technology | Previous Version | Current Version | Primary Additions |
|---|---|---|---|---|
| `Bauhaven-Platform` | Supabase / PostgreSQL | Migration `0047` | Migration `0053` | Migrations `0048`–`0053`: user deletion, `u_code` trigger, attendance recurrence/roster, finance linking, balance views & RLS |
| `Bauhaven-Admin-Web` | Next.js 16 (App Router) | `0.1.0` | `0.1.1` | Multi-day attendance scheduler, individual audience targeting, enrollment payment progress bar, user deletion |
| `Bauhaven-Academy-Web` | Next.js 16 (App Router) | `0.1.0` | `0.1.1` | `TuitionCoverageCard`, tuition query engine, fractional coverage tracking, expiration alerts |
| `bauhaven_ft` | Flutter (Mobile) | `1.1.1+6` | `1.1.2+7` | Search and link registered user profiles during participant creation; record payments with `payerProfileId` |
| `bauhaven-admin` | Flutter (Mobile) | `1.2.1+7` | `1.2.2+8` | `_EnrollmentFinanceBadge` with linear progress indicator beside enrollment names, tuition totals |
| `bauhaven-hub2` | Flutter (Mobile) | `1.1.0+2` | `1.1.1+3` | `tuition_providers.dart`, `TuitionCoverageCard` on home dashboard tracking coverage expiration |

---

## 6. Verification & Test Summary

- **`Bauhaven-Admin-Web`**: 51 test suites, 526 tests passed; TypeScript check (`tsc --noEmit`) clean; Next.js production build succeeded with zero errors.
- **`Bauhaven-Academy-Web`**: 5 unit tests for tuition queries passed; TypeScript check clean; Next.js production build succeeded in 2.3s.
- **`bauhaven_ft`**: Participant linking unit tests passed; `flutter test` clean.
- **`bauhaven-admin`**: 50/50 tests passed; `dart analyze lib` reports zero issues.
- **`bauhaven-hub2`**: `dart analyze lib/features/home` reports zero issues.
- **Database**: All migrations applied and verified against remote Supabase project `keyaahfksbfigcdbbuda`.
