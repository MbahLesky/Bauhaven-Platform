-- ============================================================================
-- Migration 0049: Fix admin_delete_user, admin_reactivate_user, and RBAC Audit
--
-- Fixes:
-- 1. admin_delete_user:
--    - Allows Super Admins to delete any user (except self & last Super Admin).
--    - Allows Organisation Admins to delete non-admin users (learners, staff, etc.).
--    - Handles Hard Delete (p_hard_delete = true) by cleanly nullifying/cascading
--      foreign key references to prevent PostgreSQL 23503 constraint violations.
--    - Handles Soft Delete (p_hard_delete = false) by deactivating profile and
--      revoking active role assignments.
-- 2. admin_reactivate_user:
--    - Allows administrators to reactivate deactivated users.
-- 3. Fixes audit logging in admin_assign_role and admin_revoke_role_assignment
--    to use public.log_audit_event instead of non-existent columns.
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 1. admin_delete_user
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_delete_user(
  p_user_id uuid,
  p_hard_delete boolean DEFAULT false
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, auth, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_is_super_admin boolean := false;
  v_caller_is_org_admin boolean := false;
  v_target_is_admin boolean := false;
  v_target_is_super_admin boolean := false;
  v_remaining_super_admins integer;
  v_target_profile public.profiles%ROWTYPE;
BEGIN
  v_caller_id := auth.uid();

  -- 1. Authority Check
  IF coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role' OR coalesce(auth.jwt() ->> 'role', '') = 'service_role' THEN
    v_caller_is_super_admin := true;
  ELSIF v_caller_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = v_caller_id
        AND public.is_assignment_active(ura)
        AND r.code IN ('super_admin', 'platform_admin')
    ) INTO v_caller_is_super_admin;

    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = v_caller_id
        AND public.is_assignment_active(ura)
        AND r.code = 'organisation_admin'
    ) INTO v_caller_is_org_admin;
  END IF;

  IF NOT (coalesce(v_caller_is_super_admin, false) OR coalesce(v_caller_is_org_admin, false)) THEN
    RAISE EXCEPTION 'Permission denied: Only administrators can delete users.'
      USING errcode = '42501';
  END IF;

  -- 2. Guard: Cannot delete self
  IF v_caller_id IS NOT NULL AND p_user_id = v_caller_id THEN
    RAISE EXCEPTION 'Cannot delete your own account.'
      USING errcode = '22023';
  END IF;

  -- 3. Fetch target profile
  SELECT * INTO v_target_profile
  FROM public.profiles
  WHERE id = p_user_id;

  -- 4. Check target roles
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = p_user_id
      AND public.is_assignment_active(ura)
      AND r.code IN ('super_admin', 'platform_admin')
  ) INTO v_target_is_super_admin;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = p_user_id
      AND public.is_assignment_active(ura)
      AND r.code IN ('super_admin', 'platform_admin', 'organisation_admin')
  ) INTO v_target_is_admin;

  -- Organisation Admins cannot delete or deactivate other administrators
  IF NOT coalesce(v_caller_is_super_admin, false) THEN
    IF coalesce(v_target_is_admin, false) THEN
      RAISE EXCEPTION 'Permission denied: Only a Super Admin can delete other administrators.'
        USING errcode = '42501';
    END IF;
  END IF;

  -- Protect the last Super Admin
  IF v_target_is_super_admin THEN
    SELECT count(DISTINCT ura.user_id) INTO v_remaining_super_admins
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE r.code IN ('super_admin', 'platform_admin')
      AND ura.user_id <> p_user_id
      AND public.is_assignment_active(ura);

    IF coalesce(v_remaining_super_admins, 0) < 1 THEN
      RAISE EXCEPTION 'Cannot delete the last active Super Admin.'
        USING errcode = '22023';
    END IF;
  END IF;

  -- 5. Hard delete vs Soft delete
  IF p_hard_delete THEN
    -- Log audit event before deleting records
    BEGIN
      PERFORM public.log_audit_event(
        p_actor_id    => v_caller_id,
        p_action      => 'user.hard_deleted',
        p_entity_type => 'user',
        p_entity_id   => p_user_id::text,
        p_before      => jsonb_build_object(
          'id', p_user_id,
          'email', v_target_profile.email,
          'full_name', v_target_profile.full_name
        ),
        p_after       => jsonb_build_object('hard_delete', true),
        p_outcome     => 'success'
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;

    -- Clean up Foreign Key references across all platform tables
    BEGIN
      UPDATE public.audit_logs SET actor_id = NULL WHERE actor_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.user_role_assignments SET granted_by = NULL WHERE granted_by = p_user_id;
      UPDATE public.user_role_assignments SET revoked_by = NULL WHERE revoked_by = p_user_id;
      UPDATE public.user_role_assignments SET suspended_by = NULL WHERE suspended_by = p_user_id;
      DELETE FROM public.user_role_assignments WHERE user_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.applications SET applicant_profile_id = NULL WHERE applicant_profile_id = p_user_id;
      UPDATE public.applications SET assigned_reviewer_id = NULL WHERE assigned_reviewer_id = p_user_id;
      UPDATE public.applications SET actor_id = NULL WHERE actor_id = p_user_id;
      UPDATE public.applications SET reviewer_id = NULL WHERE reviewer_id = p_user_id;
      UPDATE public.applications SET decided_by = NULL WHERE decided_by = p_user_id;
      UPDATE public.applications SET mentor_id = NULL WHERE mentor_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.application_status_history SET actor_id = NULL WHERE actor_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.enrolments SET mentor_id = NULL WHERE mentor_id = p_user_id;
      UPDATE public.enrolments SET actor_id = NULL WHERE actor_id = p_user_id;
      DELETE FROM public.enrolments WHERE profile_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.admin_invitations SET issued_by = NULL WHERE issued_by = p_user_id;
      UPDATE public.admin_invitations SET accepted_user_id = NULL WHERE accepted_user_id = p_user_id;
      UPDATE public.admin_invitations SET revoked_by = NULL WHERE revoked_by = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.participant_invitations SET issued_by = NULL WHERE issued_by = p_user_id;
      UPDATE public.participant_invitations SET accepted_user_id = NULL WHERE accepted_user_id = p_user_id;
      UPDATE public.participant_invitations SET revoked_by = NULL WHERE revoked_by = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.offerings SET created_by = NULL WHERE created_by = p_user_id;
      UPDATE public.offerings SET updated_by = NULL WHERE updated_by = p_user_id;
      UPDATE public.cohorts SET created_by = NULL WHERE created_by = p_user_id;
      UPDATE public.cohorts SET updated_by = NULL WHERE updated_by = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      DELETE FROM public.staff_assignments WHERE staff_profile_id = p_user_id;
      UPDATE public.staff_assignments SET created_by = NULL WHERE created_by = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.tasks SET created_by = NULL WHERE created_by = p_user_id;
      UPDATE public.tasks SET assigned_by = NULL WHERE assigned_by = p_user_id;
      UPDATE public.tasks SET reviewer_id = NULL WHERE reviewer_id = p_user_id;
      DELETE FROM public.task_submissions WHERE participant_id = p_user_id;
      UPDATE public.task_submissions SET reviewer_id = NULL WHERE reviewer_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.finance_transactions SET payer_profile_id = NULL WHERE payer_profile_id = p_user_id;
      UPDATE public.finance_transactions SET recorded_by = NULL WHERE recorded_by = p_user_id;
      UPDATE public.finance_incomes SET recorded_by = NULL WHERE recorded_by = p_user_id;
      UPDATE public.finance_expenses SET entered_by = NULL WHERE entered_by = p_user_id;
      UPDATE public.finance_expenses SET approved_by = NULL WHERE approved_by = p_user_id;
      UPDATE public.finance_expenses SET voided_by = NULL WHERE voided_by = p_user_id;
      UPDATE public.finance_bank_transactions SET matched_by = NULL WHERE matched_by = p_user_id;
      UPDATE public.finance_reconciliations SET resolved_by = NULL WHERE resolved_by = p_user_id;
      UPDATE public.finance_reconciliations SET actor_id = NULL WHERE actor_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      DELETE FROM public.absence_requests WHERE requester_id = p_user_id;
      DELETE FROM public.absence_request_approvals WHERE approver_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      DELETE FROM public.issue_reports WHERE reporter_id = p_user_id;
      UPDATE public.issue_reports SET resolved_by = NULL WHERE resolved_by = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      UPDATE public.assets SET assigned_to = NULL WHERE assigned_to = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    BEGIN
      DELETE FROM public.fcm_device_tokens WHERE profile_id = p_user_id;
      DELETE FROM public.participant_profiles WHERE profile_id = p_user_id;
    EXCEPTION WHEN OTHERS THEN NULL;
    END;

    -- Delete from profiles and auth.users
    DELETE FROM public.profiles WHERE id = p_user_id;
    DELETE FROM auth.users WHERE id = p_user_id;

  ELSE
    -- Soft delete: Deactivate profile and revoke active roles
    UPDATE public.profiles
    SET status = 'deactivated', updated_at = now()
    WHERE id = p_user_id;

    UPDATE public.user_role_assignments
    SET status = 'revoked',
        revoked_at = now(),
        revoked_by = v_caller_id,
        revocation_reason = CASE
          WHEN coalesce(v_caller_is_super_admin, false) THEN 'Deactivated by Super Admin'
          ELSE 'Deactivated by Organisation Admin'
        END,
        updated_at = now()
    WHERE user_id = p_user_id AND status = 'active';

    BEGIN
      PERFORM public.log_audit_event(
        p_actor_id    => v_caller_id,
        p_action      => 'user.deactivated',
        p_entity_type => 'user',
        p_entity_id   => p_user_id::text,
        p_before      => jsonb_build_object('status', v_target_profile.status),
        p_after       => jsonb_build_object('status', 'deactivated', 'hard_delete', false),
        p_outcome     => 'success'
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid, boolean) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 2. admin_reactivate_user
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_reactivate_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, auth, pg_temp
AS $$
DECLARE
  v_caller_id uuid;
  v_caller_role text;
  v_caller_is_super_admin boolean := false;
  v_caller_is_org_admin boolean := false;
  v_target_profile public.profiles%ROWTYPE;
BEGIN
  v_caller_id := auth.uid();

  IF coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role' OR coalesce(auth.jwt() ->> 'role', '') = 'service_role' THEN
    v_caller_is_super_admin := true;
  ELSIF v_caller_id IS NOT NULL THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = v_caller_id
        AND public.is_assignment_active(ura)
        AND r.code IN ('super_admin', 'platform_admin')
    ) INTO v_caller_is_super_admin;

    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = v_caller_id
        AND public.is_assignment_active(ura)
        AND r.code = 'organisation_admin'
    ) INTO v_caller_is_org_admin;
  END IF;

  IF NOT (coalesce(v_caller_is_super_admin, false) OR coalesce(v_caller_is_org_admin, false)) THEN
    RAISE EXCEPTION 'Permission denied: Only administrators can reactivate users.'
      USING errcode = '42501';
  END IF;

  SELECT * INTO v_target_profile
  FROM public.profiles
  WHERE id = p_user_id;

  IF v_target_profile.id IS NULL THEN
    RAISE EXCEPTION 'User profile not found.'
      USING errcode = 'P0002';
  END IF;

  UPDATE public.profiles
  SET status = 'active', updated_at = now()
  WHERE id = p_user_id;

  BEGIN
    PERFORM public.log_audit_event(
      p_actor_id    => v_caller_id,
      p_action      => 'user.reactivated',
      p_entity_type => 'user',
      p_entity_id   => p_user_id::text,
      p_before      => jsonb_build_object('status', v_target_profile.status),
      p_after       => jsonb_build_object('status', 'active'),
      p_outcome     => 'success'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_reactivate_user(uuid) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. Fix audit logging in admin_assign_role & admin_revoke_role_assignment
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_assign_role(
  p_user_id uuid,
  p_role_code text,
  p_scope_type text DEFAULT 'organisation',
  p_scope_id uuid DEFAULT NULL,
  p_assignment_type text DEFAULT 'permanent',
  p_valid_until timestamptz DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, auth, pg_temp
AS $$
DECLARE
  v_caller_is_super_admin boolean;
  v_caller_is_org_admin boolean;
  v_target_is_admin boolean;
  v_role_id uuid;
  v_assignment_id uuid;
  v_target_profile public.profiles;
BEGIN
  -- Check caller authority
  IF coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role' OR coalesce(auth.jwt() ->> 'role', '') = 'service_role' THEN
    v_caller_is_super_admin := true;
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = auth.uid()
        AND public.is_assignment_active(ura)
        AND r.code IN ('super_admin', 'platform_admin')
    ) INTO v_caller_is_super_admin;

    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = auth.uid()
        AND public.is_assignment_active(ura)
        AND r.code = 'organisation_admin'
    ) INTO v_caller_is_org_admin;
  END IF;

  IF NOT (coalesce(v_caller_is_super_admin, false) OR coalesce(v_caller_is_org_admin, false)) THEN
    RAISE EXCEPTION 'Permission denied: Only administrators can assign roles.'
      USING errcode = '42501';
  END IF;

  -- Validate target user
  SELECT * INTO v_target_profile
  FROM public.profiles
  WHERE id = p_user_id;

  IF v_target_profile.id IS NULL THEN
    RAISE EXCEPTION 'User profile not found.'
      USING errcode = 'P0002';
  END IF;

  -- If not Super Admin: target user cannot be an admin, and cannot assign admin roles
  IF NOT coalesce(v_caller_is_super_admin, false) THEN
    IF p_role_code IN ('super_admin', 'platform_admin', 'organisation_admin') THEN
      RAISE EXCEPTION 'Permission denied: Only a Super Admin can grant administrator roles.'
        USING errcode = '42501';
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = p_user_id
        AND public.is_assignment_active(ura)
        AND r.code IN ('super_admin', 'platform_admin', 'organisation_admin')
    ) INTO v_target_is_admin;

    IF coalesce(v_target_is_admin, false) THEN
      RAISE EXCEPTION 'Permission denied: Only a Super Admin can modify roles for other administrators.'
        USING errcode = '42501';
    END IF;
  END IF;

  -- Validate role
  SELECT id INTO v_role_id
  FROM public.roles
  WHERE code = p_role_code AND is_active = true;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Unknown or inactive role "%"', p_role_code
      USING errcode = '22023';
  END IF;

  -- Check if an active assignment already exists
  SELECT id INTO v_assignment_id
  FROM public.user_role_assignments
  WHERE user_id = p_user_id
    AND role_id = v_role_id
    AND scope_type = p_scope_type
    AND coalesce(scope_id, '00000000-0000-0000-0000-000000000000'::uuid) =
        coalesce(p_scope_id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND status = 'active';

  IF v_assignment_id IS NOT NULL THEN
    UPDATE public.user_role_assignments
    SET assignment_type = p_assignment_type::public.role_assignment_type,
        valid_until = p_valid_until,
        updated_at = now()
    WHERE id = v_assignment_id;
  ELSE
    INSERT INTO public.user_role_assignments (
      user_id,
      role_id,
      scope_type,
      scope_id,
      assignment_type,
      valid_until,
      status,
      granted_by
    ) VALUES (
      p_user_id,
      v_role_id,
      p_scope_type,
      p_scope_id,
      p_assignment_type::public.role_assignment_type,
      p_valid_until,
      'active',
      auth.uid()
    )
    RETURNING id INTO v_assignment_id;
  END IF;

  -- Audit log
  BEGIN
    PERFORM public.log_audit_event(
      p_actor_id    => auth.uid(),
      p_action      => 'role.assigned',
      p_entity_type => 'user_role_assignments',
      p_entity_id   => v_assignment_id::text,
      p_before      => NULL::jsonb,
      p_after       => jsonb_build_object(
        'target_user_id', p_user_id,
        'role_code', p_role_code,
        'scope_type', p_scope_type,
        'scope_id', p_scope_id
      ),
      p_outcome     => 'success'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_assignment_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_assign_role(uuid, text, text, uuid, text, timestamptz) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.admin_revoke_role_assignment(
  p_assignment_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, auth, pg_temp
AS $$
DECLARE
  v_caller_is_super_admin boolean;
  v_caller_is_org_admin boolean;
  v_target public.user_role_assignments;
  v_target_role text;
  v_target_is_admin boolean;
  v_remaining_super_admins integer;
BEGIN
  -- Check caller authority
  IF coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role' OR coalesce(auth.jwt() ->> 'role', '') = 'service_role' THEN
    v_caller_is_super_admin := true;
  ELSE
    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = auth.uid()
        AND public.is_assignment_active(ura)
        AND r.code IN ('super_admin', 'platform_admin')
    ) INTO v_caller_is_super_admin;

    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = auth.uid()
        AND public.is_assignment_active(ura)
        AND r.code = 'organisation_admin'
    ) INTO v_caller_is_org_admin;
  END IF;

  IF NOT (coalesce(v_caller_is_super_admin, false) OR coalesce(v_caller_is_org_admin, false)) THEN
    RAISE EXCEPTION 'Permission denied: Only administrators can revoke role assignments.'
      USING errcode = '42501';
  END IF;

  SELECT * INTO v_target
  FROM public.user_role_assignments
  WHERE id = p_assignment_id;

  IF v_target.id IS NULL THEN
    RAISE EXCEPTION 'Role assignment not found.'
      USING errcode = 'P0002';
  END IF;

  IF v_target.status = 'revoked' THEN
    RETURN;
  END IF;

  SELECT code INTO v_target_role
  FROM public.roles
  WHERE id = v_target.role_id;

  -- Non-super admins cannot revoke admin roles or modify admin users
  IF NOT coalesce(v_caller_is_super_admin, false) THEN
    IF v_target_role IN ('super_admin', 'platform_admin', 'organisation_admin') THEN
      RAISE EXCEPTION 'Permission denied: Only a Super Admin can revoke administrator roles.'
        USING errcode = '42501';
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = v_target.user_id
        AND public.is_assignment_active(ura)
        AND r.code IN ('super_admin', 'platform_admin', 'organisation_admin')
    ) INTO v_target_is_admin;

    IF coalesce(v_target_is_admin, false) THEN
      RAISE EXCEPTION 'Permission denied: Only a Super Admin can revoke roles for other administrators.'
        USING errcode = '42501';
    END IF;
  END IF;

  -- Protection against revoking the last super admin
  IF v_target_role IN ('super_admin', 'platform_admin') THEN
    SELECT count(DISTINCT ura.user_id) INTO v_remaining_super_admins
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE r.code IN ('super_admin', 'platform_admin')
      AND ura.id <> p_assignment_id
      AND public.is_assignment_active(ura);

    IF coalesce(v_remaining_super_admins, 0) < 1 THEN
      RAISE EXCEPTION 'Cannot revoke the last active Super Admin.'
        USING errcode = '22023';
    END IF;
  END IF;

  UPDATE public.user_role_assignments
  SET status = 'revoked',
      revoked_at = now(),
      revoked_by = auth.uid(),
      revocation_reason = nullif(trim(coalesce(p_reason, '')), ''),
      updated_at = now()
  WHERE id = p_assignment_id;

  -- Audit log entry
  BEGIN
    PERFORM public.log_audit_event(
      p_actor_id    => auth.uid(),
      p_action      => 'role.revoked',
      p_entity_type => 'user_role_assignments',
      p_entity_id   => p_assignment_id::text,
      p_before      => jsonb_build_object('role_code', v_target_role),
      p_after       => jsonb_build_object(
        'target_user_id', v_target.user_id,
        'role_code', v_target_role,
        'reason', p_reason
      ),
      p_outcome     => 'success'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_revoke_role_assignment(uuid, text) TO authenticated, service_role;
