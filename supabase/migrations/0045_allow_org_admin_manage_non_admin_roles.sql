-- ============================================================================
-- Migration 0045: Allow Organisation Admins to Manage Non-Admin User Roles
--
-- Business Rules:
-- 1. Super Admin can assign and revoke any role for any user.
-- 2. Organisation Admin can assign and revoke roles ONLY for users who are NOT
--    administrators (neither super_admin nor organisation_admin).
-- 3. Organisation Admin cannot grant or revoke administrator roles
--    (super_admin, organisation_admin).
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 1. admin_assign_role
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
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = auth.uid()
      AND public.is_assignment_active(ura)
      AND r.code = 'super_admin'
  ) INTO v_caller_is_super_admin;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = auth.uid()
      AND public.is_assignment_active(ura)
      AND r.code = 'organisation_admin'
  ) INTO v_caller_is_org_admin;

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
    IF p_role_code IN ('super_admin', 'organisation_admin') THEN
      RAISE EXCEPTION 'Permission denied: Only a Super Admin can grant administrator roles.'
        USING errcode = '42501';
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = p_user_id
        AND public.is_assignment_active(ura)
        AND r.code IN ('super_admin', 'organisation_admin')
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
    SET assignment_type = p_assignment_type,
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
      p_assignment_type,
      p_valid_until,
      'active',
      auth.uid()
    )
    RETURNING id INTO v_assignment_id;
  END IF;

  -- Audit log entry
  INSERT INTO public.audit_logs (
    event_type,
    user_id,
    table_name,
    record_id,
    new_data
  ) VALUES (
    'role.assigned',
    auth.uid(),
    'user_role_assignments',
    v_assignment_id,
    jsonb_build_object(
      'target_user_id', p_user_id,
      'role_code', p_role_code,
      'scope_type', p_scope_type,
      'scope_id', p_scope_id,
      'assigned_by', auth.uid()
    )
  );

  RETURN v_assignment_id;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2. admin_revoke_role_assignment
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_revoke_role_assignment(
  p_assignment_id uuid,
  p_reason text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, pg_temp
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
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = auth.uid()
      AND public.is_assignment_active(ura)
      AND r.code = 'super_admin'
  ) INTO v_caller_is_super_admin;

  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = auth.uid()
      AND public.is_assignment_active(ura)
      AND r.code = 'organisation_admin'
  ) INTO v_caller_is_org_admin;

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
    IF v_target_role IN ('super_admin', 'organisation_admin') THEN
      RAISE EXCEPTION 'Permission denied: Only a Super Admin can revoke administrator roles.'
        USING errcode = '42501';
    END IF;

    SELECT EXISTS (
      SELECT 1
      FROM public.user_role_assignments ura
      JOIN public.roles r ON r.id = ura.role_id
      WHERE ura.user_id = v_target.user_id
        AND public.is_assignment_active(ura)
        AND r.code IN ('super_admin', 'organisation_admin')
    ) INTO v_target_is_admin;

    IF coalesce(v_target_is_admin, false) THEN
      RAISE EXCEPTION 'Permission denied: Only a Super Admin can revoke roles for other administrators.'
        USING errcode = '42501';
    END IF;
  END IF;

  -- Protection against revoking the last super admin
  IF v_target_role = 'super_admin' THEN
    SELECT count(DISTINCT ura.user_id) INTO v_remaining_super_admins
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE r.code = 'super_admin'
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
  INSERT INTO public.audit_logs (
    event_type,
    user_id,
    table_name,
    record_id,
    new_data
  ) VALUES (
    'role.revoked',
    auth.uid(),
    'user_role_assignments',
    p_assignment_id,
    jsonb_build_object(
      'target_user_id', v_target.user_id,
      'role_code', v_target_role,
      'reason', p_reason,
      'revoked_by', auth.uid()
    )
  );
END;
$$;

