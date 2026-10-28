-- ============================================================================
-- Migration 0047: Learner Invitations & Enrolments Self-Service Schema
--
-- 1. Makes `enrolments.profile_id` nullable so an enrolment record can be staged
--    at approval time (`pending_activation`) without forcing premature creation
--    of a passwordless `auth.users` account.
-- 2. Adds `token` column on `invitations` so the clean activation code (e.g. BAU-XXXXXX)
--    is directly readable and queryable alongside `token_hash`.
-- ============================================================================

-- 1. Allow profile_id to be null on enrolments until the participant sets their password
ALTER TABLE public.enrolments ALTER COLUMN profile_id DROP NOT NULL;

-- 2. Add plain token column on invitations for human-readable admission code
ALTER TABLE public.invitations ADD COLUMN IF NOT EXISTS token text;

CREATE INDEX IF NOT EXISTS invitations_token_idx ON public.invitations (token);
CREATE INDEX IF NOT EXISTS invitations_token_hash_idx ON public.invitations (token_hash);
