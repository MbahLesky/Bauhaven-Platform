-- ============================================================================
-- Migration 0042: Super Admin Exclusive Role and User Management
--
-- Founder Directive:
-- "super admin should be able to edit roles and delete users.
--  And should be the only person able to do so"
--
-- Restricts role assignment, role revocation, and user deletion exclusively
-- to 'super_admin'. Organisation Admin and other roles are prevented from
-- performing these actions.
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 1. admin_assign_role: Super Admin assigns or updates a user's role
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
  v_role_id uuid;
  v_assignment_id uuid;
  v_target_profile public.profiles;
BEGIN
  -- Strict guard: ONLY Super Admin can assign or edit roles
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = auth.uid()
      AND public.is_assignment_active(ura)
      AND r.code = 'super_admin'
  ) INTO v_caller_is_super_admin;

  IF NOT coalesce(v_caller_is_super_admin, false) THEN
    RAISE EXCEPTION 'Permission denied: Only a Super Admin can edit or assign roles.'
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

  -- Validate role
  SELECT id INTO v_role_id
  FROM public.roles
  WHERE code = p_role_code AND is_active = true;

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Unknown or inactive role "%"', p_role_code
      USING errcode = '22023';
  END IF;

  -- Check if an assignment already exists for this exact user + role + scope
  SELECT id INTO v_assignment_id
  FROM public.user_role_assignments
  WHERE user_id = p_user_id
    AND role_id = v_role_id
    AND scope_type = coalesce(p_scope_type, 'organisation')
    AND (
      (scope_id IS NULL AND p_scope_id IS NULL)
      OR scope_id = p_scope_id
    )
  LIMIT 1;

  IF v_assignment_id IS NOT NULL THEN
    -- Reactivate or update existing assignment
    UPDATE public.user_role_assignments
    SET status = 'active',
        assigned_by = auth.uid(),
        assignment_type = coalesce(p_assignment_type, 'permanent'),
        valid_from = now(),
        valid_until = p_valid_until,
        revoked_at = NULL,
        revoked_by = NULL,
        revocation_reason = NULL,
        updated_at = now()
    WHERE id = v_assignment_id;
  ELSE
    -- Insert new assignment
    INSERT INTO public.user_role_assignments (
      user_id,
      role_id,
      scope_type,
      scope_id,
      assigned_by,
      assignment_type,
      valid_from,
      valid_until,
      status
    )
    VALUES (
      p_user_id,
      v_role_id,
      coalesce(p_scope_type, 'organisation'),
      p_scope_id,
      auth.uid(),
      coalesce(p_assignment_type, 'permanent'),
      now(),
      p_valid_until,
      'active'
    )
    RETURNING id INTO v_assignment_id;
  END IF;

  -- Audit log event
  PERFORM public.log_audit_event(
    auth.uid(),
    'role.assigned',
    'user_role_assignment',
    v_assignment_id,
    NULL,
    jsonb_build_object(
      'target_user_id', p_user_id,
      'role_code', p_role_code,
      'scope_type', p_scope_type,
      'scope_id', p_scope_id,
      'assignment_type', p_assignment_type,
      'valid_until', p_valid_until
    ),
    'success',
    jsonb_build_object('assigned_by', auth.uid()),
    NULL
  );

  RETURN v_assignment_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_assign_role(uuid, text, text, uuid, text, timestamptz) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2. admin_revoke_role_assignment: Super Admin ONLY
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
  v_target public.user_role_assignments;
  v_target_role text;
  v_remaining_super_admins integer;
BEGIN
  -- Strict guard: ONLY Super Admin can revoke role assignments
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = auth.uid()
      AND public.is_assignment_active(ura)
      AND r.code = 'super_admin'
  ) INTO v_caller_is_super_admin;

  IF NOT coalesce(v_caller_is_super_admin, false) THEN
    RAISE EXCEPTION 'Permission denied: Only a Super Admin can revoke role assignments.'
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

  -- Safety check: never revoke the last Super Admin
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
      revocation_reason = coalesce(p_reason, 'Revoked by Super Admin'),
      updated_at = now()
  WHERE id = p_assignment_id;

  PERFORM public.log_audit_event(
    auth.uid(),
    'role.revoked',
    'user_role_assignment',
    p_assignment_id,
    jsonb_build_object('role_id', v_target.role_id, 'user_id', v_target.user_id),
    jsonb_build_object('status', 'revoked', 'reason', p_reason),
    'success',
    NULL,
    NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_revoke_role_assignment(uuid, text) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3. admin_delete_user: Super Admin ONLY
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
  v_caller_is_super_admin boolean;
  v_target_is_super_admin boolean;
  v_remaining_super_admins integer;
BEGIN
  -- Strict guard: ONLY Super Admin can delete or deactivate users
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = auth.uid()
      AND public.is_assignment_active(ura)
      AND r.code = 'super_admin'
  ) INTO v_caller_is_super_admin;

  IF NOT coalesce(v_caller_is_super_admin, false) THEN
    RAISE EXCEPTION 'Permission denied: Only a Super Admin can delete users.'
      USING errcode = '42501';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete your own account.'
      USING errcode = '22023';
  END IF;

  -- Safety check: never delete the last Super Admin
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = p_user_id
      AND public.is_assignment_active(ura)
      AND r.code = 'super_admin'
  ) INTO v_target_is_super_admin;

  IF v_target_is_super_admin THEN
    SELECT count(DISTINCT ura.user_id) INTO v_remaining_super_admins
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE r.code = 'super_admin'
      AND ura.user_id <> p_user_id
      AND public.is_assignment_active(ura);

    IF coalesce(v_remaining_super_admins, 0) < 1 THEN
      RAISE EXCEPTION 'Cannot delete the last active Super Admin.'
        USING errcode = '22023';
    END IF;
  END IF;

  IF p_hard_delete THEN
    -- Permanently delete from auth.users (cascades to public.profiles)
    DELETE FROM auth.users WHERE id = p_user_id;
  ELSE
    -- Deactivate profile and revoke all active assignments
    UPDATE public.profiles
    SET status = 'deactivated', updated_at = now()
    WHERE id = p_user_id;

    UPDATE public.user_role_assignments
    SET status = 'revoked',
        revoked_at = now(),
        revoked_by = auth.uid(),
        revocation_reason = 'Deactivated by Super Admin',
        updated_at = now()
    WHERE user_id = p_user_id AND status = 'active';
  END IF;

  PERFORM public.log_audit_event(
    auth.uid(),
    CASE WHEN p_hard_delete THEN 'user.hard_deleted' ELSE 'user.deactivated' END,
    'user',
    p_user_id,
    NULL,
    jsonb_build_object('hard_delete', p_hard_delete),
    'success',
    NULL,
    NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid, boolean) TO authenticated;
