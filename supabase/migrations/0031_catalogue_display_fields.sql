-- Renumbered 2026-09-11: this was `0010_catalogue_display_fields.sql` on MbahLesky/Bauhaven-admin `main`
-- (see 0029 for why). Already applied to keyaahfksbfigcdbbuda - do not re-run it there.
--
-- Bauhaven - Catalogue display fields needed by Hub
--
-- 0003_catalogue.sql created offerings and cohorts as a deliberate stub: its
-- own header says it is "intentionally NOT the full Offerings/Cohorts admin
-- module". That was fine while only Admissions used them as a foreign-key
-- target. Hub actually displays them, and the columns it needs are absent:
--
--   offerings has no summary, description, delivery_mode or location_text
--   cohorts   has no delivery_mode
--
-- Without these, Hub's programme screen can show a title and nothing else.
--
-- These are additive. Nothing is renamed and nothing is dropped, so Admin and
-- the Admissions flow are unaffected.
--
-- Deliberately NOT changed here, because Admin depends on the current names and
-- renaming them would break it. Hub's DTOs read the live names instead:
--   profiles.full_name    (BAU-DB-002 says display_name / first_name / last_name)
--   profiles.email        (BAU-DB-002 says primary_email)
--   profiles.phone        (BAU-DB-002 says phone_e164)
--   profiles.avatar_url   (BAU-DB-002 says avatar_path)
--   profiles.status       (BAU-DB-002 says account_status)
--   enrolments.activated_at / started_at / completed_at
--                         (BAU-DB-002 says enrolled_at / starts_at / completion_at)
--
-- That divergence should be reconciled in BAU-DB-002 rather than in the
-- database; see docs/architecture/backend-dependencies.md section 5.

alter table public.offerings
  add column if not exists summary text,
  add column if not exists description text,
  add column if not exists delivery_mode text,
  add column if not exists location_text text;

comment on column public.offerings.summary is
  'Short public-facing description. Shown on Hub''s programme card.';
comment on column public.offerings.delivery_mode is
  'onsite, online or hybrid (BAU-DB-002 section 7.1).';

alter table public.cohorts
  add column if not exists delivery_mode text;

comment on column public.cohorts.delivery_mode is
  'Optional override of the offering''s delivery mode (BAU-DB-002 section 7.2).';

-- Hub needs an end date for its "days remaining" progress indicator. Cohorts
-- already carry start/end dates; enrolments do not, and an enrolment can end
-- before its cohort does (withdrawal, early completion). ends_at is added so
-- that case is representable rather than inferred.
alter table public.enrolments
  add column if not exists ends_at timestamptz;

comment on column public.enrolments.ends_at is
  'When this participant''s enrolment ends, if it differs from the cohort end.';
