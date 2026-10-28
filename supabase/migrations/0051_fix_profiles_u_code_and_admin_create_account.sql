-- ============================================================================
-- Migration 0051: Fix profiles u_code NOT NULL constraint and admin_create_account
--
-- Fixes:
-- 1. Adds DEFAULT to public.profiles.u_code so any insert into profiles
--    automatically receives a unique 8-character u_code if omitted.
-- 2. Adds DEFAULT to public.profiles.role ('applicant').
-- 3. Updates public.admin_create_account to explicitly provide u_code and
--    properly handle ON CONFLICT updates.
-- ============================================================================

-- -----------------------------------------------------------------------------
-- 1. Set column defaults on public.profiles
-- -----------------------------------------------------------------------------
ALTER TABLE public.profiles
  ALTER COLUMN u_code SET DEFAULT substr(replace(gen_random_uuid()::text, '-', ''), 1, 8);

ALTER TABLE public.profiles
  ALTER COLUMN role SET DEFAULT 'applicant';

-- Backfill any profile with missing or empty u_code
UPDATE public.profiles
SET u_code = substr(replace(id::text, '-', ''), 1, 8)
WHERE u_code IS NULL OR trim(u_code) = '';

-- -----------------------------------------------------------------------------
-- 2. Update public.handle_new_auth_user trigger function
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth, pg_temp
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, status, role, u_code)
  VALUES (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name', ''),
    coalesce(new.email, ''),
    'pending',
    'applicant',
    substr(replace(new.id::text, '-', ''), 1, 8)
  )
  ON CONFLICT (id) DO UPDATE
    SET full_name = CASE
          WHEN coalesce(public.profiles.full_name, '') = '' THEN EXCLUDED.full_name
          ELSE public.profiles.full_name
        END,
        email = EXCLUDED.email,
        u_code = coalesce(public.profiles.u_code, EXCLUDED.u_code),
        updated_at = now();
  RETURN new;
END;
$$;

-- -----------------------------------------------------------------------------
-- 3. Update public.admin_create_account
-- -----------------------------------------------------------------------------
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
  v_is_service_role boolean := false;
BEGIN
  -- Determine caller authority
  IF coalesce(auth.role(), '') = 'service_role' OR current_user = 'service_role' OR coalesce(auth.jwt() ->> 'role', '') = 'service_role' THEN
    v_caller_role := 'super_admin';
    v_is_service_role := true;
  ELSE
    SELECT r.code INTO v_caller_role
    FROM public.user_role_assignments ura
    JOIN public.roles r ON r.id = ura.role_id
    WHERE ura.user_id = auth.uid()
      AND public.is_assignment_active(ura)
      AND r.code IN ('super_admin', 'platform_admin', 'organisation_admin')
    ORDER BY CASE WHEN r.code IN ('super_admin', 'platform_admin') THEN 1 ELSE 2 END
    LIMIT 1;
  END IF;

  IF v_caller_role IS NULL THEN
    RAISE EXCEPTION 'Only an Admin can create an account directly.'
      USING errcode = '42501';
  END IF;

  -- Organisation Admin cannot create or grant Super Admin or Organisation Admin
  IF v_caller_role = 'organisation_admin' AND p_role_code IN ('super_admin', 'platform_admin', 'organisation_admin') THEN
    RAISE EXCEPTION 'Organisation Admins cannot grant administrator roles.'
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

  -- 1. Create user in auth.users
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

  -- 2. Create identity in auth.identities
  INSERT INTO auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) VALUES (
    v_user_id::text,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
    'email',
    now(), now(), now()
  );

  -- 3. Create or update profile with u_code
  INSERT INTO public.profiles (id, full_name, email, role, status, u_code)
  VALUES (
    v_user_id,
    v_name,
    v_email,
    CASE WHEN p_role_code = 'learner' THEN 'student' ELSE 'admin' END,
    'active',
    substr(replace(v_user_id::text, '-', ''), 1, 8)
  )
  ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        email = EXCLUDED.email,
        status = 'active',
        u_code = coalesce(public.profiles.u_code, EXCLUDED.u_code),
        updated_at = now();

  -- 4. Grant staff role assignment
  IF v_role_id IS NOT NULL THEN
    INSERT INTO public.user_role_assignments (
      user_id, role_id, scope_type, scope_id, granted_by,
      assignment_type, valid_from, status
    ) VALUES (
      v_user_id, v_role_id, coalesce(p_scope_type, 'organisation'), p_scope_id, auth.uid(),
      'permanent', now(), 'active'
    );
  END IF;

  -- 5. Create active enrolment for learners
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

  -- 6. Audit log
  BEGIN
    PERFORM public.log_audit_event(
      p_actor_id    => auth.uid(),
      p_action      => 'user.created_directly',
      p_entity_type => 'user',
      p_entity_id   => v_user_id::text,
      p_before      => NULL::jsonb,
      p_after       => jsonb_build_object(
        'email', v_email,
        'full_name', v_name,
        'role_code', p_role_code
      ),
      p_outcome     => 'success'
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_create_account(text, text, text, text, text, uuid, uuid, uuid, text) TO authenticated, service_role;
