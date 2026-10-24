-- =============================================================================
-- BAUHAVEN: REALIGN ROLES, PERMISSIONS & INITIAL USER ASSIGNMENTS
-- =============================================================================
-- Run this in your Supabase Dashboard -> SQL Editor
-- =============================================================================

BEGIN;

-- 1. Ensure Additional Granular Permissions Exist
INSERT INTO public.permissions (code, domain, name, description, risk_level) VALUES
  ('tasks.read', 'learning', 'Read tasks', 'View task catalog and assignments.', 'low'),
  ('attendance.read', 'attendance', 'Read attendance', 'View attendance registers and session logs.', 'low'),
  ('assets.read', 'resources', 'Read assets', 'View equipment and resource catalog.', 'low'),
  ('cms.read', 'website', 'Read website content', 'View website CMS entries and sections.', 'low'),
  ('users.manage', 'governance', 'Manage users', 'Add, edit, deactivate and manage staff and learner profiles.', 'high')
ON CONFLICT (code) DO NOTHING;

-- 2. Upsert the Active Role Catalogue
INSERT INTO public.roles (code, name, description, is_active) VALUES
  ('super_admin', 'Super Admin', 'Highest approved platform governance with unrestricted access.', true),
  ('organisation_admin', 'Organisation Admin', 'Full platform operational governance excluding finance approval.', true),
  ('programme_manager', 'Program Manager', 'Academic and internship leadership across offerings, cohorts, tasks, and admissions.', true),
  ('application_reviewer', 'Application Reviewer', 'Reviews, scores, evaluates, and decides applicant admissions.', true),
  ('mentor_supervisor', 'Supervisor', 'Assigned cohort mentors and supervisors managing attendance, tasks, grading, and feedback.', true),
  ('finance_manager', 'Finance Manager', 'Full treasury and financial operations, approvals, ledgers, and fee plans.', true),
  ('content_manager', 'Content Manager', 'Publishes and edits www.bauhaven.com marketing and CMS content.', true),
  ('asset_manager', 'Asset Manager', 'Manages physical and digital lab equipment and inventory.', true),
  ('auditor', 'Auditor', 'Read-only compliance, audit log review, and financial reporting.', true),
  ('task_manager', 'Task Manager', 'Assigns tasks, tracks submissions, and manages reminders.', true),
  ('attendance_personnel', 'Attendance Personnel', 'Creates attendance sessions and records/corrects attendance logs.', true),
  ('staff', 'Staff', 'General staff with task tracking, attendance, view-only directory/applications/assets/content, and finance entry.', true)
ON CONFLICT (code) DO UPDATE
  SET name = EXCLUDED.name,
      description = EXCLUDED.description,
      is_active = true;

-- Deactivate internship_coordinator (migrated to programme_manager)
UPDATE public.roles
SET is_active = false,
    description = 'Deprecated: Merged into Program Manager.'
WHERE code = 'internship_coordinator';

-- Reassign any existing internship_coordinator role assignments to programme_manager
DO $$
DECLARE
  v_old_role uuid;
  v_new_role uuid;
BEGIN
  SELECT id INTO v_old_role FROM public.roles WHERE code = 'internship_coordinator';
  SELECT id INTO v_new_role FROM public.roles WHERE code = 'programme_manager';

  IF v_old_role IS NOT NULL AND v_new_role IS NOT NULL THEN
    UPDATE public.user_role_assignments
    SET role_id = v_new_role, updated_at = now()
    WHERE role_id = v_old_role;
  END IF;
END $$;

-- 3. Reset and Rebuild Role-Permission Mappings
DELETE FROM public.role_permissions
WHERE role_id IN (
  SELECT id FROM public.roles
  WHERE code IN (
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

-- Super Admin: ALL permissions across all domains
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
CROSS JOIN public.permissions p
WHERE r.code = 'super_admin'
ON CONFLICT DO NOTHING;

-- Organisation Admin:
--   * Full operational control across all domains (admissions, LMS, attendance, CMS, assets, user management)
--   * Roles assignment/revocation (restricted by RPC to exclude super_admin and organisation_admin)
--   * Finance: CAN ONLY enter income, expenses, charges (entry-only; CANNOT approve, void, or reverse)
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN (
    -- Admissions
    'applications.read', 'applications.view', 'applications.review', 'applications.decide', 'applications.approve', 'applications.notes.manage',
    -- People & Governance
    'participants.read', 'participants.manage', 'users.manage', 'roles.assign', 'roles.revoke', 'audit.read', 'settings.manage',
    -- Programmes & Academics
    'programmes.manage', 'cohorts.manage',
    -- Learning / Tasks
    'tasks.create', 'tasks.assign', 'tasks.read', 'submissions.review', 'feedback.release',
    -- Attendance
    'attendance.record', 'attendance.correct', 'attendance.read',
    -- CMS
    'cms.publish', 'cms.read',
    -- Assets
    'assets.manage', 'assets.read',
    -- Finance (Entry & Read ONLY)
    'finance.dashboard.read', 'finance.participants.read', 'finance.charges.read', 'finance.charges.create',
    'finance.payments.read', 'finance.income.read', 'finance.income.create', 'finance.expenses.read',
    'finance.expenses.create', 'finance.petty_cash.create'
  )
)
WHERE r.code = 'organisation_admin'
ON CONFLICT DO NOTHING;

-- Program Manager: Academic offerings, cohorts, tasks, submissions, feedback, attendance, and admissions
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN (
    'applications.read', 'applications.view', 'applications.review', 'applications.decide', 'applications.approve', 'applications.notes.manage',
    'participants.read', 'participants.manage',
    'programmes.manage', 'cohorts.manage',
    'tasks.create', 'tasks.assign', 'tasks.read', 'submissions.review', 'feedback.release',
    'attendance.record', 'attendance.correct', 'attendance.read'
  )
)
WHERE r.code = 'programme_manager'
ON CONFLICT DO NOTHING;

-- Application Reviewer: Can review AND approve applications
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN (
    'applications.read', 'applications.view', 'applications.review', 'applications.decide', 'applications.approve', 'applications.notes.manage',
    'participants.read'
  )
)
WHERE r.code = 'application_reviewer'
ON CONFLICT DO NOTHING;

-- Supervisor (Mentor/Supervisor): Cohort tasks, submissions, grading, feedback, attendance
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN (
    'participants.read',
    'tasks.assign', 'tasks.read', 'submissions.review', 'feedback.release',
    'attendance.record', 'attendance.correct', 'attendance.read'
  )
)
WHERE r.code = 'mentor_supervisor'
ON CONFLICT DO NOTHING;

-- Finance Manager: Complete treasury, approvals, and financial management
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.domain = 'finance' AND p.code <> 'finance.migration.review'
)
WHERE r.code = 'finance_manager'
ON CONFLICT DO NOTHING;

-- Content Manager: CMS publishing and text management
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN ('cms.publish', 'cms.read')
)
WHERE r.code = 'content_manager'
ON CONFLICT DO NOTHING;

-- Asset Manager: Lab and equipment register
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN ('assets.manage', 'assets.read')
)
WHERE r.code = 'asset_manager'
ON CONFLICT DO NOTHING;

-- Auditor: Read-only audit logs, reports, and financial dashboard
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN ('audit.read', 'finance.dashboard.read', 'finance.reports.read')
)
WHERE r.code = 'auditor'
ON CONFLICT DO NOTHING;

-- Task Manager: Task creation, assignment, submissions, and reminders
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN ('tasks.create', 'tasks.assign', 'tasks.read', 'submissions.review', 'participants.read')
)
WHERE r.code = 'task_manager'
ON CONFLICT DO NOTHING;

-- Attendance Personnel: Sessions and attendance records
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN ('attendance.record', 'attendance.correct', 'attendance.read', 'participants.read')
)
WHERE r.code = 'attendance_personnel'
ON CONFLICT DO NOTHING;

-- Staff: Task tracking, attendance, view-only directory/applications/assets/content, and finance entry
INSERT INTO public.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM public.roles r
JOIN public.permissions p ON (
  p.code IN (
    'tasks.create', 'tasks.assign', 'tasks.read', 'submissions.review',
    'attendance.record', 'attendance.correct', 'attendance.read',
    'assets.read', 'applications.read', 'applications.view', 'participants.read', 'cms.read',
    'finance.dashboard.read', 'finance.participants.read', 'finance.charges.read', 'finance.charges.create',
    'finance.payments.read', 'finance.income.read', 'finance.income.create', 'finance.expenses.read',
    'finance.expenses.create', 'finance.petty_cash.create'
  )
)
WHERE r.code = 'staff'
ON CONFLICT DO NOTHING;

-- 4. Update public.is_admin(uid uuid)
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

-- 5. Update admin_create_account RPC
CREATE OR REPLACE FUNCTION public.admin_create_account(
  p_email text,
  p_password text,
  p_name text,
  p_role_code text,
  p_scope_type text DEFAULT 'organisation',
  p_scope_id uuid DEFAULT NULL,
  p_offering_id uuid DEFAULT NULL,
  p_cohort_id uuid DEFAULT NULL,
  p_assigned_role text DEFAULT 'Student'
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, auth, extensions, pg_temp
AS $$
DECLARE
  v_user_id uuid;
  v_role_id uuid;
  v_email text := lower(trim(p_email));
  v_name text := trim(p_name);
  v_caller_role text;
BEGIN
  -- Determine caller authority
  SELECT r.code INTO v_caller_role
  FROM public.user_role_assignments ura
  JOIN public.roles r ON r.id = ura.role_id
  WHERE ura.user_id = auth.uid()
    AND public.is_assignment_active(ura)
    AND r.code IN ('super_admin', 'organisation_admin')
  ORDER BY CASE WHEN r.code = 'super_admin' THEN 1 ELSE 2 END
  LIMIT 1;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION 'Only an Admin can create an account directly.'
      USING errcode = '42501';
  END IF;

  -- Organisation Admin cannot create or grant Super Admin or Organisation Admin
  IF v_caller_role = 'organisation_admin' AND p_role_code IN ('super_admin', 'organisation_admin') THEN
    RAISE EXCEPTION 'Organisation Admins cannot grant Super Admin or Organisation Admin roles.'
      USING errcode = '42501';
  END IF;

  IF p_role_code <> 'learner' THEN
    SELECT id INTO v_role_id
    FROM public.roles
    WHERE code = p_role_code AND is_active = true;

    IF v_role_id IS NULL THEN
      RAISE EXCEPTION 'Unknown or inactive role %.', p_role_code
        USING errcode = '22023';
    END IF;
  ELSE
    IF p_offering_id IS NULL OR p_cohort_id IS NULL THEN
      RAISE EXCEPTION 'A learner account requires a programme and cohort.'
        USING errcode = '22023';
    END IF;
  END IF;

  IF v_email IS NULL OR v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' THEN
    RAISE EXCEPTION 'That does not look like an email address.'
      USING errcode = '22023';
  END IF;

  IF v_name IS NULL OR length(v_name) < 2 THEN
    RAISE EXCEPTION 'Enter the person''s name.'
      USING errcode = '22023';
  END IF;

  IF p_password IS NULL OR length(p_password) < 8 THEN
    RAISE EXCEPTION 'Password must be at least 8 characters.'
      USING errcode = '22023';
  END IF;

  IF EXISTS (SELECT 1 FROM auth.users WHERE lower(email) = v_email) THEN
    RAISE EXCEPTION 'An account with this email address already exists.'
      USING errcode = '23505';
  END IF;

  v_user_id := gen_random_uuid();

  -- Create user in auth.users
  INSERT INTO auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) VALUES (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    crypt(p_password, gen_salt('bf')),
    now(),
    '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('full_name', v_name, 'name', v_name),
    now(),
    now()
  );

  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_user_id::text,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
    'email',
    now(), now(), now()
  );

  -- Profile
  INSERT INTO public.profiles (id, full_name, email, role, status)
  VALUES (
    v_user_id,
    v_name,
    v_email,
    CASE WHEN p_role_code = 'learner' THEN 'student' ELSE 'admin' END,
    'active'
  )
  ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        email = EXCLUDED.email,
        status = 'active',
        updated_at = now();

  -- Grant staff role assignment
  IF v_role_id IS NOT NULL THEN
    INSERT INTO public.user_role_assignments (
      user_id, role_id, scope_type, scope_id, granted_by,
      assignment_type, valid_from, status
    ) VALUES (
      v_user_id, v_role_id, p_scope_type, p_scope_id, auth.uid(),
      'permanent', now(), 'active'
    );
  END IF;

  -- Create active enrolment for learners
  IF p_role_code = 'learner' AND p_offering_id IS NOT NULL AND p_cohort_id IS NOT NULL THEN
    INSERT INTO public.enrolments (
      profile_id, offering_id, cohort_id, assigned_role, status, activated_at, started_at
    ) VALUES (
      v_user_id,
      p_offering_id,
      p_cohort_id,
      coalesce(nullif(trim(p_assigned_role), ''), 'Student'),
      'active',
      now(),
      CURRENT_DATE
    );
  END IF;

  RETURN v_user_id;
END;
$$;

-- 6. Update admin_revoke_role_assignment RPC
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
  v_caller_role text;
  v_target public.user_role_assignments;
  v_target_role text;
  v_remaining_super_admins integer;
BEGIN
  -- Determine caller authority
  SELECT r.code INTO v_caller_role
  FROM public.user_role_assignments ura
  JOIN public.roles r ON r.id = ura.role_id
  WHERE ura.user_id = auth.uid()
    AND public.is_assignment_active(ura)
    AND r.code IN ('super_admin', 'organisation_admin')
  ORDER BY CASE WHEN r.code = 'super_admin' THEN 1 ELSE 2 END
  LIMIT 1;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION 'Permission denied: Only an Admin can revoke role assignments.'
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

  -- Organisation Admin cannot revoke Super Admin or Organisation Admin
  IF v_caller_role = 'organisation_admin' AND v_target_role IN ('super_admin', 'organisation_admin') THEN
    RAISE EXCEPTION 'Organisation Admins cannot revoke Super Admin or Organisation Admin roles.'
      USING errcode = '42501';
  END IF;

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
      revocation_reason = nullif(trim(coalesce(p_reason, '')), ''),
      updated_at = now()
  WHERE id = p_assignment_id;
END;
$$;

-- 7. Add admin_delete_user RPC
CREATE OR REPLACE FUNCTION public.admin_delete_user(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, private, auth, pg_temp
AS $$
DECLARE
  v_caller_role text;
  v_target_has_protected_role boolean;
BEGIN
  -- Determine caller authority
  SELECT r.code INTO v_caller_role
  FROM public.user_role_assignments ura
  JOIN public.roles r ON r.id = ura.role_id
  WHERE ura.user_id = auth.uid()
    AND public.is_assignment_active(ura)
    AND r.code IN ('super_admin', 'organisation_admin')
  ORDER BY CASE WHEN r.code = 'super_admin' THEN 1 ELSE 2 END
  LIMIT 1;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION 'Permission denied: Only an Admin can delete or deactivate users.'
      USING errcode = '42501';
  END IF;

  IF p_user_id = auth.uid() THEN
    RAISE EXCEPTION 'Cannot delete or deactivate your own account.'
      USING errcode = '22023';
  END IF;

  -- Check if target user holds super_admin or organisation_admin
  SELECT EXISTS (
    SELECT 1
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = p_user_id
      AND public.is_assignment_active(ura)
      AND r.code IN ('super_admin', 'organisation_admin')
  ) INTO v_target_has_protected_role;

  IF v_caller_role = 'organisation_admin' AND v_target_has_protected_role THEN
    RAISE EXCEPTION 'Organisation Admins cannot edit, deactivate or delete a Super Admin or another Organisation Admin.'
      USING errcode = '42501';
  END IF;

  -- Deactivate profile and revoke all active assignments
  UPDATE public.profiles
  SET status = 'deactivated', updated_at = now()
  WHERE id = p_user_id;

  UPDATE public.user_role_assignments
  SET status = 'revoked',
      revoked_at = now(),
      revoked_by = auth.uid(),
      revocation_reason = 'Deactivated by administrator',
      updated_at = now()
  WHERE user_id = p_user_id AND status = 'active';
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_delete_user(uuid) TO authenticated;

-- 8. Synchronize the 3 Initial Accounts
DO $$
DECLARE
  v_primary_id        uuid;
  v_jam_id            uuid;
  v_mbah_id           uuid;
  v_super_admin_role  uuid;
  v_org_admin_role    uuid;
  v_finance_role      uuid;
BEGIN
  -- Resolve IDs from auth.users or profiles
  SELECT id INTO v_primary_id FROM auth.users WHERE lower(email) = 'bauhaventc@gmail.com' LIMIT 1;
  IF v_primary_id IS NULL THEN
    SELECT id INTO v_primary_id FROM public.profiles WHERE lower(email) = 'bauhaventc@gmail.com' LIMIT 1;
  END IF;

  SELECT id INTO v_jam_id FROM auth.users WHERE lower(email) = 'jamrandyankiambom@gmail.com' LIMIT 1;
  IF v_jam_id IS NULL THEN
    SELECT id INTO v_jam_id FROM public.profiles WHERE lower(email) = 'jamrandyankiambom@gmail.com' LIMIT 1;
  END IF;

  SELECT id INTO v_mbah_id FROM auth.users WHERE lower(email) = 'mbahlesky2@gmail.com' LIMIT 1;
  IF v_mbah_id IS NULL THEN
    SELECT id INTO v_mbah_id FROM public.profiles WHERE lower(email) = 'mbahlesky2@gmail.com' LIMIT 1;
  END IF;

  SELECT id INTO v_super_admin_role FROM public.roles WHERE code = 'super_admin';
  SELECT id INTO v_org_admin_role   FROM public.roles WHERE code = 'organisation_admin';
  SELECT id INTO v_finance_role     FROM public.roles WHERE code = 'finance_manager';

  -- 1) bauhaventc@gmail.com -> ONLY Super Admin
  IF v_primary_id IS NOT NULL AND v_super_admin_role IS NOT NULL THEN
    UPDATE public.profiles SET role = 'admin', status = 'active', updated_at = now() WHERE id = v_primary_id;

    -- Revoke non-super_admin assignments
    UPDATE public.user_role_assignments
    SET status = 'revoked', revoked_at = now(), updated_at = now()
    WHERE user_id = v_primary_id AND role_id <> v_super_admin_role AND status = 'active';

    -- Ensure active super_admin
    INSERT INTO public.user_role_assignments (
      user_id, role_id, scope_type, scope_id, granted_by, assignment_type, valid_from, status
    ) VALUES (
      v_primary_id, v_super_admin_role, 'organisation', NULL, v_primary_id, 'permanent', now(), 'active'
    )
    ON CONFLICT DO NOTHING;

    UPDATE public.user_role_assignments
    SET status = 'active', revoked_at = NULL, updated_at = now()
    WHERE user_id = v_primary_id AND role_id = v_super_admin_role;
  END IF;

  -- 2) mbahlesky2@gmail.com -> ONLY Organisation Admin
  IF v_mbah_id IS NOT NULL AND v_org_admin_role IS NOT NULL THEN
    UPDATE public.profiles SET role = 'admin', status = 'active', updated_at = now() WHERE id = v_mbah_id;

    -- Revoke super_admin if previously granted
    UPDATE public.user_role_assignments
    SET status = 'revoked', revoked_at = now(), updated_at = now()
    WHERE user_id = v_mbah_id AND role_id = v_super_admin_role AND status = 'active';

    -- Ensure active organisation_admin
    INSERT INTO public.user_role_assignments (
      user_id, role_id, scope_type, scope_id, granted_by, assignment_type, valid_from, status
    ) VALUES (
      v_mbah_id, v_org_admin_role, 'organisation', NULL, coalesce(v_primary_id, v_mbah_id), 'permanent', now(), 'active'
    )
    ON CONFLICT DO NOTHING;

    UPDATE public.user_role_assignments
    SET status = 'active', revoked_at = NULL, updated_at = now()
    WHERE user_id = v_mbah_id AND role_id = v_org_admin_role;
  END IF;

  -- 3) jamrandyankiambom@gmail.com -> Organisation Admin + Finance Manager
  IF v_jam_id IS NOT NULL AND v_org_admin_role IS NOT NULL AND v_finance_role IS NOT NULL THEN
    UPDATE public.profiles SET role = 'admin', status = 'active', updated_at = now() WHERE id = v_jam_id;

    -- Revoke super_admin if previously granted
    UPDATE public.user_role_assignments
    SET status = 'revoked', revoked_at = now(), updated_at = now()
    WHERE user_id = v_jam_id AND role_id = v_super_admin_role AND status = 'active';

    -- Ensure active organisation_admin
    INSERT INTO public.user_role_assignments (
      user_id, role_id, scope_type, scope_id, granted_by, assignment_type, valid_from, status
    ) VALUES (
      v_jam_id, v_org_admin_role, 'organisation', NULL, coalesce(v_primary_id, v_jam_id), 'permanent', now(), 'active'
    )
    ON CONFLICT DO NOTHING;

    UPDATE public.user_role_assignments
    SET status = 'active', revoked_at = NULL, updated_at = now()
    WHERE user_id = v_jam_id AND role_id = v_org_admin_role;

    -- Ensure active finance_manager
    INSERT INTO public.user_role_assignments (
      user_id, role_id, scope_type, scope_id, granted_by, assignment_type, valid_from, status
    ) VALUES (
      v_jam_id, v_finance_role, 'organisation', NULL, coalesce(v_primary_id, v_jam_id), 'permanent', now(), 'active'
    )
    ON CONFLICT DO NOTHING;

    UPDATE public.user_role_assignments
    SET status = 'active', revoked_at = NULL, updated_at = now()
    WHERE user_id = v_jam_id AND role_id = v_finance_role;
  END IF;
END $$;

COMMIT;

