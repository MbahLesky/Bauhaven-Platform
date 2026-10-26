-- ============================================================================
-- Migration 0044: Restore RBAC Functions, Fix is_admin, and Re-activate Admin Roles
--
-- Restores public.is_admin and private.has_permission to correctly query
-- public.user_role_assignments (Governance v2) instead of the legacy empty
-- user_roles table, ensuring all Admin Portal RLS policies function correctly.
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 1. Restore private.has_permission
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.has_permission(
  p_code text,
  p_scope_type text DEFAULT 'organisation',
  p_scope_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.role_permissions rp ON rp.role_id = ura.role_id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE ura.user_id = auth.uid()
      AND p.code = p_code
      AND public.is_assignment_active(ura)
      AND (
        ura.scope_type = 'organisation'
        OR (ura.scope_type = p_scope_type AND ura.scope_id = p_scope_id)
      )
  );
$$;

-- -----------------------------------------------------------------------------
-- 2. Restore public.is_admin(uid uuid)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin(uid uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = uid
      AND public.is_assignment_active(ura)
      AND r.code IN (
        'super_admin',
        'organisation_admin',
        'programme_manager',
        'application_reviewer',
        'mentor_supervisor',
        'finance_manager',
        'content_manager',
        'asset_manager',
        'auditor',
        'task_manager',
        'attendance_personnel',
        'staff'
      )
  );
$$;

-- -----------------------------------------------------------------------------
-- 3. Restore public.has_permission_for (for Edge Functions / service_role)
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_permission_for(
  p_user_id uuid,
  p_code text,
  p_scope_type text DEFAULT 'organisation',
  p_scope_id uuid DEFAULT NULL
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, private, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    JOIN public.role_permissions rp ON rp.role_id = r.id
    JOIN public.permissions p ON p.id = rp.permission_id
    WHERE ura.user_id = p_user_id
      AND p.code = p_code
      AND public.is_assignment_active(ura)
      AND (
        ura.scope_type = 'organisation'
        OR (ura.scope_type = p_scope_type AND ura.scope_id = p_scope_id)
      )
  );
$$;

REVOKE ALL ON FUNCTION public.has_permission_for(uuid, text, text, uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.has_permission_for(uuid, text, text, uuid) TO service_role;

-- -----------------------------------------------------------------------------
-- 4. Reactivate Super Admin & Organisation Admin for Founder / Admin Accounts
-- -----------------------------------------------------------------------------
-- Reactivate super_admin on mbahlesky2@gmail.com
UPDATE public.user_role_assignments
SET status = 'active',
    revoked_at = NULL,
    revoked_by = NULL,
    revocation_reason = NULL,
    valid_from = LEAST(valid_from, now()),
    valid_until = NULL,
    updated_at = now()
WHERE user_id = 'f0bec947-5d22-42c6-93a6-58a38d966553'
  AND role_id = (SELECT id FROM public.roles WHERE code = 'super_admin');

-- Reactivate super_admin on bauhaventc@gmail.com
UPDATE public.user_role_assignments
SET status = 'active',
    revoked_at = NULL,
    revoked_by = NULL,
    revocation_reason = NULL,
    valid_from = LEAST(valid_from, now()),
    valid_until = NULL,
    updated_at = now()
WHERE user_id = '670cbbe0-ebbf-499c-b362-40b82276b68d'
  AND role_id = (SELECT id FROM public.roles WHERE code = 'super_admin');

-- Ensure organisation_admin is active on mbahlesky2@gmail.com
UPDATE public.user_role_assignments
SET status = 'active',
    revoked_at = NULL,
    revoked_by = NULL,
    revocation_reason = NULL,
    valid_from = LEAST(valid_from, now()),
    valid_until = NULL,
    updated_at = now()
WHERE user_id = 'f0bec947-5d22-42c6-93a6-58a38d966553'
  AND role_id = (SELECT id FROM public.roles WHERE code = 'organisation_admin');

