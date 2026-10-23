-- Bauhaven Admin - Row Level Security
--
-- Principle: every table below has RLS enabled. Read access for
-- admin-console data is gated by public.is_admin(auth.uid()) (any of
-- platform_admin/program_manager/reviewer); a couple of writes are gated by
-- the more granular private.has_permission() where the schema doc calls for
-- it. Privileged writes (role grants, approvals, invitations, enrolment
-- creation) have NO client-facing INSERT/UPDATE policy at all - they only
-- happen through the approve-application Edge Function's service-role
-- client, which bypasses RLS entirely. idempotency_keys has RLS enabled
-- with zero policies, so no non-service role can read or write it at all.

alter table public.profiles enable row level security;
alter table public.roles enable row level security;
alter table public.permissions enable row level security;
alter table public.role_permissions enable row level security;
alter table public.user_roles enable row level security;
alter table public.offerings enable row level security;
alter table public.cohorts enable row level security;
alter table public.applications enable row level security;
alter table public.application_status_history enable row level security;
alter table public.application_reviews enable row level security;
alter table public.application_approvals enable row level security;
alter table public.invitations enable row level security;
alter table public.enrolments enable row level security;
alter table public.enrolment_status_history enable row level security;
alter table public.audit_logs enable row level security;
alter table public.idempotency_keys enable row level security;

-- Defense in depth: the live `applications` table was found with a raw
-- table-level UPDATE grant to anon/authenticated (Supabase's dashboard
-- table editor grants broad privileges by default; nothing in
-- bauhaven-website's own code performs an anon/authenticated UPDATE on
-- this table - Apply.js only ever INSERTs, and the admin API route there
-- uses the service-role key, which bypasses grants and RLS alike). RLS with
-- no matching UPDATE policy for those roles already blocks this, but the
-- grant is revoked too rather than relying on RLS alone.
revoke update on public.applications from anon, authenticated;

-- profiles ---------------------------------------------------------------
drop policy if exists profiles_select_self_or_admin on public.profiles;
create policy profiles_select_self_or_admin on public.profiles
  for select
  using (private.is_self(id) or public.is_admin(auth.uid()));

drop policy if exists profiles_update_self_or_admin on public.profiles;
create policy profiles_update_self_or_admin on public.profiles
  for update
  using (private.is_self(id) or public.is_admin(auth.uid()))
  with check (private.is_self(id) or public.is_admin(auth.uid()));

-- roles / permissions / role_permissions (reference data) ------------------
drop policy if exists roles_select_admin on public.roles;
create policy roles_select_admin on public.roles for select using (public.is_admin(auth.uid()));

drop policy if exists permissions_select_admin on public.permissions;
create policy permissions_select_admin on public.permissions for select using (public.is_admin(auth.uid()));

drop policy if exists role_permissions_select_admin on public.role_permissions;
create policy role_permissions_select_admin on public.role_permissions for select using (public.is_admin(auth.uid()));

-- user_roles -----------------------------------------------------------
drop policy if exists user_roles_select_self_or_admin on public.user_roles;
create policy user_roles_select_self_or_admin on public.user_roles
  for select
  using (private.is_self(user_id) or public.is_admin(auth.uid()));

-- No INSERT/UPDATE/DELETE policy: role grants are only ever written by
-- service-role code (see supabase/functions/approve-application).

-- offerings / cohorts (admin-operational lookup, not the public website
-- catalogue - see 0003_catalogue.sql header) ---------------------------
drop policy if exists offerings_select_admin on public.offerings;
create policy offerings_select_admin on public.offerings for select using (public.is_admin(auth.uid()));

drop policy if exists cohorts_select_admin on public.cohorts;
create policy cohorts_select_admin on public.cohorts for select using (public.is_admin(auth.uid()));

-- applications -----------------------------------------------------------
-- SECURITY FIX: the live `applications` table was found with RLS disabled
-- entirely and a pre-existing dashboard-created policy named "Public can
-- read applications" (SELECT, using true) - meaning all 83 real applicants'
-- names/emails/phone numbers were readable by anyone holding the public
-- anon key, with no restriction at all. Enabling RLS above does not remove
-- that policy by itself (Postgres OR's every policy for the same command
-- together), so it must be dropped explicitly or it would keep granting
-- public read access alongside the admin-only policy this migration adds.
drop policy if exists "Public can read applications" on public.applications;

-- "Public can apply" (INSERT, with check true) already did exactly what
-- applications_insert_public below does - dropped so there isn't a second,
-- differently-named policy performing the same insert grant.
drop policy if exists "Public can apply" on public.applications;

-- Public application forms (bauhaven-website) must be able to submit a new
-- application without being signed in, matching the existing website
-- behaviour documented in SUPABASE_SETUP.md.
drop policy if exists applications_insert_public on public.applications;
create policy applications_insert_public on public.applications
  for insert
  with check (true);

drop policy if exists applications_select_admin on public.applications;
create policy applications_select_admin on public.applications
  for select
  using (public.is_admin(auth.uid()));

drop policy if exists applications_update_decision on public.applications;
create policy applications_update_decision on public.applications
  for update
  using (private.has_permission('applications.decide'))
  with check (private.has_permission('applications.decide'));

-- application_status_history / application_approvals / invitations --------
-- (append-only / decision-record tables: readable by admins, written only
-- by triggers or the service-role Edge Function)
drop policy if exists application_status_history_select_admin on public.application_status_history;
create policy application_status_history_select_admin on public.application_status_history
  for select using (public.is_admin(auth.uid()));

drop policy if exists application_approvals_select_admin on public.application_approvals;
create policy application_approvals_select_admin on public.application_approvals
  for select using (public.is_admin(auth.uid()));

drop policy if exists invitations_select_admin on public.invitations;
create policy invitations_select_admin on public.invitations
  for select using (public.is_admin(auth.uid()));

-- application_reviews (internal notes) --------------------------------
drop policy if exists application_reviews_select_admin on public.application_reviews;
create policy application_reviews_select_admin on public.application_reviews
  for select using (public.is_admin(auth.uid()));

drop policy if exists application_reviews_insert on public.application_reviews;
create policy application_reviews_insert on public.application_reviews
  for insert
  with check (private.has_permission('applications.notes.manage') and reviewer_id = auth.uid());

-- enrolments / enrolment_status_history -----------------------------------
drop policy if exists enrolments_select_admin_or_related on public.enrolments;
create policy enrolments_select_admin_or_related on public.enrolments
  for select
  using (public.is_admin(auth.uid()) or mentor_id = auth.uid() or profile_id = auth.uid());

-- No client INSERT/UPDATE/DELETE policy: enrolments are only created by the
-- approve-application Edge Function (service role, idempotent via the
-- unique index on application_id from migration 0005).

drop policy if exists enrolment_status_history_select on public.enrolment_status_history;
create policy enrolment_status_history_select on public.enrolment_status_history
  for select
  using (
    exists (
      select 1 from public.enrolments e
      where e.id = enrolment_status_history.enrolment_id
        and (public.is_admin(auth.uid()) or e.mentor_id = auth.uid() or e.profile_id = auth.uid())
    )
  );

-- audit_logs ---------------------------------------------------------------
drop policy if exists audit_logs_select_admin on public.audit_logs;
create policy audit_logs_select_admin on public.audit_logs
  for select using (public.is_admin(auth.uid()));

-- No client INSERT/UPDATE/DELETE policy anywhere: audit rows are written
-- exclusively by the SECURITY DEFINER public.log_audit_event() function, or
-- by Edge Functions using the service role. Admins cannot edit or delete
-- audit history, matching master spec section 8.20.

-- idempotency_keys: RLS enabled with zero policies above -> default deny
-- for every non-service role, by design.
