-- ============================================================================
-- Migration 0046: Fix Application Status History Trigger & Defensive Status Handling
--
-- Root Cause:
-- On the live database, `public.applications.status` is plain `text`, whereas
-- `public.application_status_history.to_status` is typed as `public.application_status` (enum).
-- When `record_application_status_change()` executed:
--   INSERT INTO public.application_status_history (..., to_status, ...)
--   VALUES (..., new.status, ...)
-- PostgreSQL threw:
--   ERROR: column "to_status" is of type application_status but expression is of type text
--
-- Fix:
-- 1. Defensively resolve `new.status` (and `old.status`) to the enum type, supporting
--    both uppercase and lowercase enum variants and standard website status aliases
--    ('pending' -> 'SUBMITTED', etc.).
-- 2. Wrap audit-logging insert in an EXCEPTION block so an audit trail side-effect
--    NEVER aborts a user's primary application submission.
-- 3. Ensure the tracking code autogen trigger exists and fires reliably.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.record_application_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
DECLARE
  v_from public.application_status;
  v_to public.application_status;
  v_raw_to text;
  v_raw_from text;
BEGIN
  v_raw_to := lower(coalesce(new.status::text, ''));

  -- Step 1: Safely resolve v_to
  BEGIN
    -- Try uppercase first (live enum contains 'SUBMITTED', 'UNDER_REVIEW', 'ACCEPTED', 'REJECTED')
    v_to := upper(new.status::text)::public.application_status;
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      -- Try lowercase
      v_to := lower(new.status::text)::public.application_status;
    EXCEPTION WHEN OTHERS THEN
      -- Map canonical aliases to uppercase enum members
      BEGIN
        v_to := CASE v_raw_to
          WHEN 'pending' THEN 'SUBMITTED'::public.application_status
          WHEN 'submitted' THEN 'SUBMITTED'::public.application_status
          WHEN 'reviewing' THEN 'UNDER_REVIEW'::public.application_status
          WHEN 'under_review' THEN 'UNDER_REVIEW'::public.application_status
          WHEN 'approved' THEN 'ACCEPTED'::public.application_status
          WHEN 'accepted' THEN 'ACCEPTED'::public.application_status
          WHEN 'rejected' THEN 'REJECTED'::public.application_status
          WHEN 'declined' THEN 'REJECTED'::public.application_status
          WHEN 'expired' THEN 'EXPIRED'::public.application_status
          ELSE NULL
        END;
      EXCEPTION WHEN OTHERS THEN
        -- Fallback to lowercase aliases if enum was created with lowercase members
        BEGIN
          v_to := CASE v_raw_to
            WHEN 'pending' THEN 'submitted'::public.application_status
            WHEN 'submitted' THEN 'submitted'::public.application_status
            WHEN 'reviewing' THEN 'under_review'::public.application_status
            WHEN 'under_review' THEN 'under_review'::public.application_status
            WHEN 'approved' THEN 'approved'::public.application_status
            WHEN 'accepted' THEN 'approved'::public.application_status
            WHEN 'rejected' THEN 'rejected'::public.application_status
            WHEN 'declined' THEN 'rejected'::public.application_status
            ELSE NULL
          END;
        EXCEPTION WHEN OTHERS THEN
          v_to := NULL;
        END;
      END;
    END;
  END;

  -- Step 2: Perform audit log insert defensively
  BEGIN
    IF tg_op = 'INSERT' THEN
      IF v_to IS NOT NULL THEN
        INSERT INTO public.application_status_history (
          application_id,
          from_status,
          to_status,
          actor_id,
          reason
        ) VALUES (
          new.id,
          NULL,
          v_to,
          auth.uid(),
          new.decision_reason
        );
      END IF;
    ELSIF tg_op = 'UPDATE' AND old.status IS DISTINCT FROM new.status THEN
      v_raw_from := lower(coalesce(old.status::text, ''));
      BEGIN
        v_from := upper(old.status::text)::public.application_status;
      EXCEPTION WHEN OTHERS THEN
        BEGIN
          v_from := lower(old.status::text)::public.application_status;
        EXCEPTION WHEN OTHERS THEN
          v_from := NULL;
        END;
      END;

      IF v_to IS NOT NULL THEN
        INSERT INTO public.application_status_history (
          application_id,
          from_status,
          to_status,
          actor_id,
          reason
        ) VALUES (
          new.id,
          v_from,
          v_to,
          auth.uid(),
          new.decision_reason
        );
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Audit trail errors should never block user application submission or updates
    RAISE WARNING 'application_status_history logging skipped: %', SQLERRM;
  END;

  RETURN new;
END;
$$;

-- Ensure trigger is attached properly
DROP TRIGGER IF EXISTS applications_record_status_history ON public.applications;
CREATE TRIGGER applications_record_status_history
  AFTER INSERT OR UPDATE ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.record_application_status_change();

-- Ensure tracking code trigger is also present and active
CREATE OR REPLACE FUNCTION public.generate_application_tracking_code()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF new.tracking_code IS NULL OR new.tracking_code = '' THEN
    new.tracking_code := 'REF-' || to_char(coalesce(new.created_at, now()), 'YYYY') || '-' || substr(new.id::text, 1, 6);
  END IF;
  RETURN new;
END;
$$;

DROP TRIGGER IF EXISTS applications_generate_tracking_code ON public.applications;
CREATE TRIGGER applications_generate_tracking_code
  BEFORE INSERT ON public.applications
  FOR EACH ROW EXECUTE FUNCTION public.generate_application_tracking_code();
