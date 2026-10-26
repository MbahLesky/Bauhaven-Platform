-- ============================================================================
-- Migration 0041: Revoke all finance access from Staff role
--
-- Founder Directive:
-- "Staff isn't supposed to see money, only people to see finance are admins"
--
-- Removes all finance domain permissions ('finance.%') from the 'staff' role.
-- Staff maintains task management, attendance tracking, and view-only access
-- to applications, assets, content, and participant directory, but has zero
-- read, write, or dashboard access to financial records, accounts, or money.
-- ============================================================================

-- 1. Remove all finance permissions from staff role
DELETE FROM public.role_permissions
WHERE role_id = (SELECT id FROM public.roles WHERE code = 'staff')
  AND permission_id IN (
    SELECT id FROM public.permissions WHERE domain = 'finance' OR code LIKE 'finance.%'
  );

-- 2. Update staff role description
UPDATE public.roles
SET description = 'General staff with task tracking, attendance, view-only directory/applications/assets/content.'
WHERE code = 'staff';