-- =========================================================
-- Applications: hold what the public form actually collects
-- =========================================================
--
-- `bauhaven-website`'s Apply form and this table were designed independently and agree on
-- almost nothing. The form was inserting `applicant_id`, which has never existed, and the
-- error that surfaced ("Could not find the 'applicant_id' column") was the smallest part
-- of the problem: of the nine fields it collects, **four** had a home here and five had
-- none, and the one that mattered most couldn't be satisfied at all.
--
-- Four separate definitions of `applications` existed across the two repos — this one,
-- the site's `SUPABASE_SETUP.md`, the site's `ENV_SETUP.md`, and the payload its code
-- actually sends. None of them matched, and the code didn't match either of its own docs.
-- This migration makes *this* table the one true definition and the site conforms to it;
-- both site docs are corrected to point here rather than carry a fifth version.
--
-- ---------------------------------------------------------
-- The substantive decision: program_id becomes nullable
-- ---------------------------------------------------------
--
-- `program_id uuid not null references programs(id)` assumed an applicant picks a row from
-- `programs`. They don't, and can't. The public site offers five **categories** —
-- 'course-training', 'internship-program', 'holiday-program', 'bootcamp-program',
-- 'career-tracks' — which are static content on the marketing site, not rows in this
-- database. Underneath them the applicant picks a *field* ("Web Development") and a level
-- ("Beginner"). Nothing in that maps to a program uuid, and inventing a mapping would have
-- to guess which of several real programs somebody meant.
--
-- So the honest model, and the one Bauhaven actually works to: **an application records
-- what the applicant asked for; a reviewer assigns the real program when they confirm it.**
-- That's what `confirmed` already means in the status flow. `program_id` therefore starts
-- null and is filled in by a human who knows which cohort has space.
--
-- Not a widening of what the table permits by accident — a correction. A required FK that
-- the only public writer cannot populate is a column that guarantees the form is broken.

alter table applications alter column program_id drop not null;

-- What the applicant actually chose, in their words. Kept as text, deliberately: these
-- are the marketing site's categories and fields, they change when the site's copy
-- changes, and freezing them into an enum here would mean a migration every time
-- Marketing adds a course.
alter table applications add column if not exists program_slug text;
alter table applications add column if not exists field_of_interest text;
alter table applications add column if not exists level text;

-- When they'd like to start and for how long. `preferred_start` is a date the applicant
-- names, distinct from anything scheduled — a reviewer may well offer a different intake.
alter table applications add column if not exists preferred_start date;
alter table applications add column if not exists duration text;

-- Anything else they wrote. The public form's free-text box, and often the only place
-- someone explains a circumstance that decides the application.
alter table applications add column if not exists message text;

comment on column applications.program_id is
  'The real programs row, assigned by a reviewer at confirm time. Null on a fresh public application — see program_slug for what the applicant actually chose.';
comment on column applications.program_slug is
  'The marketing site''s category slug (course-training, internship-program, …). Free text: these are website content, not rows in programs.';

-- Reviewers work the queue oldest-first within a status; the public site only ever
-- inserts, so this index serves Admin-web's list rather than the form.
create index if not exists idx_applications_status_created
  on applications (status, created_at);

-- ---------------------------------------------------------
-- A note on status
-- ---------------------------------------------------------
--
-- The site was sending `status: 'pending'`, which this table's check constraint has never
-- allowed — the flow is submitted → confirmed → approved/declined. That insert would have
-- failed on the constraint the moment the column-name errors were fixed, so it's worth
-- recording rather than quietly patching: the site now sends no status at all and lets the
-- column default to 'submitted', which is the correct behaviour for every client. Nothing
-- outside the review flow should be choosing a workflow state.
