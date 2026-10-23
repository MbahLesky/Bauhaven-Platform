-- =========================================================
-- Applications you can sign up for yourself
-- =========================================================
--
-- A second way in, alongside the website's anonymous form: somebody creates an account in
-- Academy with their own password, and that signup *is* their application. An Admin
-- approves it, which grants the role and the enrolment together.
--
-- This is what the website's Apply form was reaching for from the start —
-- `applicant_id: null, // set to null for now; will populate when auth is implemented`.
--
-- **Both intake paths stay.** The site keeps taking applications from people with no
-- account (`applicant_id` null); Academy signup produces one attached to an account. The
-- difference is only whether an account exists yet, so the review queue and the approval
-- flow are identical for both — the same `applications` rows, in the same statuses,
-- reviewed on the same screen.
--
-- What approval does differs, and only in the last step: an application with an
-- `applicant_id` already has an account, so approving grants the role directly. One
-- without still issues an invitation, exactly as before.

-- ---------------------------------------------------------
-- The link to an account
-- ---------------------------------------------------------

-- Nullable, permanently: an anonymous application from the public site is still a valid
-- application, and always will be. `on delete set null` rather than cascade — removing an
-- account should not silently destroy the record of an application somebody reviewed.
alter table applications
  add column if not exists applicant_id uuid references users(id) on delete set null;

create index if not exists idx_applications_applicant
  on applications (applicant_id) where applicant_id is not null;

comment on column applications.applicant_id is
  'The account that submitted this, when one exists. Null for anonymous applications from the public website. Approving an application that has one grants the role directly; without one, an invitation is issued instead.';

-- ---------------------------------------------------------
-- An applicant can see their own application
-- ---------------------------------------------------------
--
-- `applications_select` was `auth_is_admin_or_staff()` — correct while every application
-- was anonymous, and wrong the moment an applicant has an account. Somebody who signs up
-- and lands on a "we're reviewing this" screen has to be able to *read* the row that
-- screen is about; otherwise Academy can only say "you have no access" to a person whose
-- own application it is.
--
-- Replaced rather than added to, so there is one policy to read instead of two that
-- overlap.

drop policy if exists applications_select on applications;

create policy applications_select on applications for select
  using (applicant_id = auth.uid() or auth_is_admin_or_staff());

-- ---------------------------------------------------------
-- Signing up for yourself
-- ---------------------------------------------------------
--
-- `applications_insert_public` is `with check (true)`, which already permits this — a
-- signed-in user is as entitled to insert as an anonymous one. It is deliberately *not*
-- narrowed to `applicant_id = auth.uid()`, because that would break the anonymous path it
-- was written for.
--
-- The consequence, stated plainly: a signed-in user could insert an application naming
-- somebody else's `applicant_id`. That buys them nothing — it creates a row in a queue a
-- human reads, and approving it would grant a role to the *other* account, not theirs —
-- so it is noise rather than escalation. Academy's Server Action fills `applicant_id`
-- from the session regardless.

-- ---------------------------------------------------------
-- One open application at a time
-- ---------------------------------------------------------
--
-- Without this, a signup form submitted twice — or refreshed — produces two identical
-- applications, and a reviewer has to work out whether they are looking at one person
-- applying twice or one accident. Partial, so a *declined* applicant can apply again,
-- which is the decision recorded for declines: the account stays and they can re-apply.
create unique index if not exists idx_applications_one_open_per_applicant
  on applications (applicant_id)
  where applicant_id is not null and status in ('submitted', 'confirmed');
