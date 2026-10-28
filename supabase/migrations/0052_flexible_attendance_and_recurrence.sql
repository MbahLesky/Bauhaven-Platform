-- =============================================================================
-- 0052_flexible_attendance_and_recurrence.sql
-- =============================================================================
-- Extends the attendance feature:
--  1. Allows attendance sessions to target cohorts OR specific individuals
--     (including staff, admins, and learners).
--  2. Allows recurring attendance sessions grouped by series_id.
--  3. Adds profile_id to attendance_records, enabling direct attendance recording
--     for individuals who are not enrolled learners.
--  4. Creates attendance_session_attendees to track assigned individuals for
--     individual sessions.
-- =============================================================================

-- 1. attendance_sessions modifications
ALTER TABLE public.attendance_sessions
  ALTER COLUMN cohort_id DROP NOT NULL;

ALTER TABLE public.attendance_sessions
  ADD COLUMN IF NOT EXISTS target_type text NOT NULL DEFAULT 'cohort'
    CHECK (target_type IN ('cohort', 'individual')),
  ADD COLUMN IF NOT EXISTS series_id uuid DEFAULT NULL;

ALTER TABLE public.attendance_sessions
  DROP CONSTRAINT IF EXISTS attendance_sessions_cohort_target_check;

ALTER TABLE public.attendance_sessions
  ADD CONSTRAINT attendance_sessions_cohort_target_check
  CHECK ((target_type = 'cohort' AND cohort_id IS NOT NULL) OR (target_type = 'individual'));

CREATE INDEX IF NOT EXISTS attendance_sessions_series_idx
  ON public.attendance_sessions (series_id);

CREATE INDEX IF NOT EXISTS attendance_sessions_target_type_idx
  ON public.attendance_sessions (target_type);

-- 2. attendance_session_attendees (for individual sessions)
CREATE TABLE IF NOT EXISTS public.attendance_session_attendees (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  attendance_session_id uuid NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE CASCADE,
  profile_id            uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (attendance_session_id, profile_id)
);

CREATE INDEX IF NOT EXISTS attendance_session_attendees_profile_idx
  ON public.attendance_session_attendees (profile_id);

CREATE INDEX IF NOT EXISTS attendance_session_attendees_session_idx
  ON public.attendance_session_attendees (attendance_session_id);

-- 3. attendance_records modifications
ALTER TABLE public.attendance_records
  ADD COLUMN IF NOT EXISTS profile_id uuid REFERENCES public.profiles(id) ON DELETE CASCADE;

-- Backfill profile_id from enrolments for existing attendance records
UPDATE public.attendance_records ar
SET profile_id = e.profile_id
FROM public.enrolments e
WHERE ar.enrolment_id = e.id AND ar.profile_id IS NULL;

-- Make enrolment_id nullable so non-learner records (staff, admins, etc.) can be recorded
ALTER TABLE public.attendance_records
  ALTER COLUMN enrolment_id DROP NOT NULL;

-- Check that at least one of profile_id or enrolment_id is present
ALTER TABLE public.attendance_records
  DROP CONSTRAINT IF EXISTS attendance_records_target_check;

ALTER TABLE public.attendance_records
  ADD CONSTRAINT attendance_records_target_check
  CHECK (profile_id IS NOT NULL OR enrolment_id IS NOT NULL);

-- Drop old unique constraint on (attendance_session_id, enrolment_id) if present
ALTER TABLE public.attendance_records
  DROP CONSTRAINT IF EXISTS attendance_records_attendance_session_id_enrolment_id_key;

-- Unique constraint for attendance records by profile_id and session_id
ALTER TABLE public.attendance_records
  DROP CONSTRAINT IF EXISTS attendance_records_session_profile_unique;
ALTER TABLE public.attendance_records
  ADD CONSTRAINT attendance_records_session_profile_unique
  UNIQUE (attendance_session_id, profile_id);

-- Unique constraint/index for attendance records by enrolment_id and session_id (backwards compatibility)
CREATE UNIQUE INDEX IF NOT EXISTS attendance_records_session_enrolment_idx
  ON public.attendance_records (attendance_session_id, enrolment_id)
  WHERE enrolment_id IS NOT NULL;

-- 4. Permission helper functions update
CREATE OR REPLACE FUNCTION private.has_cohort_attendance_permission(
  p_code text,
  p_cohort_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
  SELECT
    public.is_admin(auth.uid())
    OR private.has_permission(p_code, 'organisation', NULL)
    OR (
      p_cohort_id IS NOT NULL AND (
        private.has_permission(p_code, 'cohort', p_cohort_id)
        OR EXISTS (
          SELECT 1
          FROM public.cohorts c
          WHERE c.id = p_cohort_id
            AND private.has_permission(p_code, 'offering', c.offering_id)
        )
      )
    );
$$;

CREATE OR REPLACE FUNCTION private.has_session_attendance_permission(
  p_code text,
  p_session_id uuid
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
  SELECT
    public.is_admin(auth.uid())
    OR private.has_permission(p_code, 'organisation', NULL)
    OR EXISTS (
      SELECT 1
      FROM public.attendance_sessions s
      WHERE s.id = p_session_id
        AND (
          (s.cohort_id IS NOT NULL AND private.has_cohort_attendance_permission(p_code, s.cohort_id))
          OR (s.cohort_id IS NULL AND (
            public.is_admin(auth.uid())
            OR private.has_permission(p_code, 'organisation', NULL)
            OR s.created_by = auth.uid()
          ))
        )
    );
$$;

REVOKE EXECUTE ON FUNCTION private.has_cohort_attendance_permission(text, uuid) FROM public;
REVOKE EXECUTE ON FUNCTION private.has_session_attendance_permission(text, uuid) FROM public;
GRANT EXECUTE ON FUNCTION private.has_cohort_attendance_permission(text, uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION private.has_session_attendance_permission(text, uuid) TO authenticated, anon;

-- 5. RLS Policies for attendance_sessions
DROP POLICY IF EXISTS attendance_sessions_select_staff ON public.attendance_sessions;
CREATE POLICY attendance_sessions_select_staff ON public.attendance_sessions
  FOR SELECT
  USING (
    public.is_admin(auth.uid())
    OR private.has_permission('attendance.record', 'organisation', NULL)
    OR private.has_permission('attendance.correct', 'organisation', NULL)
    OR (cohort_id IS NOT NULL AND (
      private.has_cohort_attendance_permission('attendance.record', cohort_id)
      OR private.has_cohort_attendance_permission('attendance.correct', cohort_id)
    ))
    OR created_by = auth.uid()
  );

DROP POLICY IF EXISTS attendance_sessions_insert_staff ON public.attendance_sessions;
CREATE POLICY attendance_sessions_insert_staff ON public.attendance_sessions
  FOR INSERT
  WITH CHECK (
    public.is_admin(auth.uid())
    OR private.has_permission('attendance.record', 'organisation', NULL)
    OR (cohort_id IS NOT NULL AND private.has_cohort_attendance_permission('attendance.record', cohort_id))
    OR (target_type = 'individual' AND auth.uid() IS NOT NULL)
  );

DROP POLICY IF EXISTS attendance_sessions_update_staff ON public.attendance_sessions;
CREATE POLICY attendance_sessions_update_staff ON public.attendance_sessions
  FOR UPDATE
  USING (
    public.is_admin(auth.uid())
    OR private.has_permission('attendance.record', 'organisation', NULL)
    OR (cohort_id IS NOT NULL AND private.has_cohort_attendance_permission('attendance.record', cohort_id))
    OR created_by = auth.uid()
  )
  WITH CHECK (
    public.is_admin(auth.uid())
    OR private.has_permission('attendance.record', 'organisation', NULL)
    OR (cohort_id IS NOT NULL AND private.has_cohort_attendance_permission('attendance.record', cohort_id))
    OR created_by = auth.uid()
  );

DROP POLICY IF EXISTS attendance_sessions_delete_staff ON public.attendance_sessions;
CREATE POLICY attendance_sessions_delete_staff ON public.attendance_sessions
  FOR DELETE
  USING (
    public.is_admin(auth.uid())
    OR private.has_permission('attendance.record', 'organisation', NULL)
    OR (cohort_id IS NOT NULL AND private.has_cohort_attendance_permission('attendance.record', cohort_id))
    OR created_by = auth.uid()
  );

DROP POLICY IF EXISTS attendance_sessions_select_participant ON public.attendance_sessions;
CREATE POLICY attendance_sessions_select_participant ON public.attendance_sessions
  FOR SELECT
  USING (
    (cohort_id IS NOT NULL AND private.is_enrolled_in_cohort(cohort_id))
    OR EXISTS (
      SELECT 1 FROM public.attendance_session_attendees asa
      WHERE asa.attendance_session_id = attendance_sessions.id
        AND asa.profile_id = auth.uid()
    )
    OR EXISTS (
      SELECT 1 FROM public.attendance_records ar
      WHERE ar.attendance_session_id = attendance_sessions.id
        AND ar.profile_id = auth.uid()
    )
  );

-- 6. RLS Policies for attendance_session_attendees
ALTER TABLE public.attendance_session_attendees ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS attendance_session_attendees_select ON public.attendance_session_attendees;
CREATE POLICY attendance_session_attendees_select ON public.attendance_session_attendees
  FOR SELECT
  USING (
    profile_id = auth.uid()
    OR public.is_admin(auth.uid())
    OR private.has_session_attendance_permission('attendance.record', attendance_session_id)
    OR private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  );

DROP POLICY IF EXISTS attendance_session_attendees_insert_staff ON public.attendance_session_attendees;
CREATE POLICY attendance_session_attendees_insert_staff ON public.attendance_session_attendees
  FOR INSERT
  WITH CHECK (
    public.is_admin(auth.uid())
    OR private.has_session_attendance_permission('attendance.record', attendance_session_id)
  );

DROP POLICY IF EXISTS attendance_session_attendees_delete_staff ON public.attendance_session_attendees;
CREATE POLICY attendance_session_attendees_delete_staff ON public.attendance_session_attendees
  FOR DELETE
  USING (
    public.is_admin(auth.uid())
    OR private.has_session_attendance_permission('attendance.record', attendance_session_id)
  );

-- 7. RLS Policies for attendance_records
DROP POLICY IF EXISTS attendance_records_select_staff ON public.attendance_records;
CREATE POLICY attendance_records_select_staff ON public.attendance_records
  FOR SELECT
  USING (
    public.is_admin(auth.uid())
    OR private.has_session_attendance_permission('attendance.record', attendance_session_id)
    OR private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  );

DROP POLICY IF EXISTS attendance_records_insert_staff ON public.attendance_records;
CREATE POLICY attendance_records_insert_staff ON public.attendance_records
  FOR INSERT
  WITH CHECK (
    public.is_admin(auth.uid())
    OR private.has_session_attendance_permission('attendance.record', attendance_session_id)
    OR private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  );

DROP POLICY IF EXISTS attendance_records_update_staff ON public.attendance_records;
CREATE POLICY attendance_records_update_staff ON public.attendance_records
  FOR UPDATE
  USING (
    public.is_admin(auth.uid())
    OR private.has_session_attendance_permission('attendance.record', attendance_session_id)
    OR private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  )
  WITH CHECK (
    public.is_admin(auth.uid())
    OR private.has_session_attendance_permission('attendance.record', attendance_session_id)
    OR private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  );

DROP POLICY IF EXISTS attendance_records_delete_staff ON public.attendance_records;
CREATE POLICY attendance_records_delete_staff ON public.attendance_records
  FOR DELETE
  USING (
    public.is_admin(auth.uid())
    OR private.has_session_attendance_permission('attendance.record', attendance_session_id)
    OR private.has_session_attendance_permission('attendance.correct', attendance_session_id)
  );

DROP POLICY IF EXISTS attendance_records_select_own ON public.attendance_records;
CREATE POLICY attendance_records_select_own ON public.attendance_records
  FOR SELECT
  USING (
    profile_id = auth.uid()
    OR (enrolment_id IS NOT NULL AND private.owns_enrolment(enrolment_id))
  );

-- Grants
GRANT SELECT, INSERT, UPDATE, DELETE ON public.attendance_sessions TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.attendance_records TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.attendance_session_attendees TO authenticated;
GRANT SELECT ON public.attendance_sessions TO anon;
GRANT SELECT ON public.attendance_records TO anon;
GRANT SELECT ON public.attendance_session_attendees TO anon;
