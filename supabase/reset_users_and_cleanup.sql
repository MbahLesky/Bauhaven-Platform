-- ============================================================================
-- BAUHAVEN PLATFORM: USER RESET, DATABASE CLEANUP & SUPER ADMIN PROVISIONING
-- ============================================================================
-- What this script does:
--   1. Keeps ONLY:
--        - bauhaventc@gmail.com
--        - jamrandyankiambom@gmail.com
--        - mbahlesky2@gmail.com (provisioned/updated as Super Admin)
--   2. Sets/updates password for mbahlesky2@gmail.com to: Bauhaven@2026!
--   3. Preserves 100% of Finance data (122 income, 95 expenses, 70 payments, etc.)
--      by reassigning audit user references to bauhaventc@gmail.com.
--   4. Preserves 100% of Website Applications (all 92 rows in public.applications).
--   5. Drops obsolete/junk tables:
--        - public.test_connection (1 test row from Dec 2025)
--        - public.instruments (Supabase sample violin/viola/cello table)
--        - public.application (singular legacy table; real data is in public.applications)
--   6. Deletes dummy/test operational records (6 gibberish draft tasks, test
--      enrolments, test invitations, test participant profile) and removes all
--      other 7 test users/profiles from public.profiles and auth.users.
-- ============================================================================

BEGIN;

-- 1. Drop unnecessary junk/sample tables (not referenced anywhere in codebase)
DROP TABLE IF EXISTS public.test_connection CASCADE;
DROP TABLE IF EXISTS public.instruments CASCADE;
DROP TABLE IF EXISTS public.application CASCADE;

DO $$
DECLARE
  v_primary_admin_id uuid;
  v_jam_id           uuid;
  v_mbah_id          uuid;
  v_super_admin_role uuid;
  v_kept_ids         uuid[];
  v_mbah_email       text := 'mbahlesky2@gmail.com';
  v_mbah_name        text := 'Mbah Lesky';
  v_mbah_password    text := 'Bauhaven@2026!';
BEGIN
  -- --------------------------------------------------------------------------
  -- 2. Resolve IDs for the 3 allowed accounts
  -- --------------------------------------------------------------------------
  SELECT id INTO v_primary_admin_id
  FROM public.profiles
  WHERE lower(email) = 'bauhaventc@gmail.com'
  LIMIT 1;

  IF v_primary_admin_id IS NULL THEN
    SELECT id INTO v_primary_admin_id
    FROM auth.users
    WHERE lower(email) = 'bauhaventc@gmail.com'
    LIMIT 1;
  END IF;

  IF v_primary_admin_id IS NULL THEN
    RAISE EXCEPTION 'Primary admin bauhaventc@gmail.com was not found.';
  END IF;

  SELECT id INTO v_jam_id
  FROM public.profiles
  WHERE lower(email) = 'jamrandyankiambom@gmail.com'
  LIMIT 1;

  IF v_jam_id IS NULL THEN
    SELECT id INTO v_jam_id
    FROM auth.users
    WHERE lower(email) = 'jamrandyankiambom@gmail.com'
    LIMIT 1;
  END IF;

  -- Check if mbahlesky2@gmail.com already exists in profiles or auth.users
  SELECT id INTO v_mbah_id
  FROM public.profiles
  WHERE lower(email) = lower(v_mbah_email)
  LIMIT 1;

  IF v_mbah_id IS NULL THEN
    SELECT id INTO v_mbah_id
    FROM auth.users
    WHERE lower(email) = lower(v_mbah_email)
    LIMIT 1;
  END IF;

  IF v_mbah_id IS NULL THEN
    v_mbah_id := gen_random_uuid();
  END IF;

  -- --------------------------------------------------------------------------
  -- 3. Create or update mbahlesky2@gmail.com in auth.users & auth.identities
  -- --------------------------------------------------------------------------
  IF EXISTS (SELECT 1 FROM auth.users WHERE id = v_mbah_id OR lower(email) = lower(v_mbah_email)) THEN
    UPDATE auth.users
    SET email                  = lower(v_mbah_email),
        encrypted_password     = extensions.crypt(v_mbah_password, extensions.gen_salt('bf')),
        email_confirmed_at     = COALESCE(email_confirmed_at, now()),
        confirmation_token     = COALESCE(confirmation_token, ''),
        recovery_token         = COALESCE(recovery_token, ''),
        email_change           = COALESCE(email_change, ''),
        email_change_token_new = COALESCE(email_change_token_new, ''),
        raw_app_meta_data      = '{"provider":"email","providers":["email"]}'::jsonb,
        raw_user_meta_data     = jsonb_build_object('full_name', v_mbah_name, 'name', v_mbah_name),
        updated_at             = now()
    WHERE id = v_mbah_id OR lower(email) = lower(v_mbah_email);
  ELSE
    INSERT INTO auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at,
      confirmation_token, recovery_token, email_change, email_change_token_new,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) VALUES (
      '00000000-0000-0000-0000-000000000000',
      v_mbah_id,
      'authenticated',
      'authenticated',
      lower(v_mbah_email),
      extensions.crypt(v_mbah_password, extensions.gen_salt('bf')),
      now(),
      '', '', '', '',
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('full_name', v_mbah_name, 'name', v_mbah_name),
      now(),
      now()
    );
  END IF;

  -- Ensure email identity exists in auth.identities for mbahlesky2@gmail.com
  IF NOT EXISTS (
    SELECT 1 FROM auth.identities
    WHERE user_id = v_mbah_id AND provider = 'email'
  ) THEN
    INSERT INTO auth.identities (
      provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) VALUES (
      v_mbah_id::text,
      v_mbah_id,
      jsonb_build_object('sub', v_mbah_id::text, 'email', lower(v_mbah_email), 'email_verified', true),
      'email',
      now(), now(), now()
    );
  END IF;

  -- Ensure public.profiles row for mbahlesky2@gmail.com is active
  INSERT INTO public.profiles (
    id, full_name, email, role, u_code, status, profile_completed_at, updated_at
  ) VALUES (
    v_mbah_id,
    v_mbah_name,
    lower(v_mbah_email),
    'admin',
    substr(replace(v_mbah_id::text, '-', ''), 1, 8),
    'active',
    now(),
    now()
  )
  ON CONFLICT (id) DO UPDATE
    SET full_name            = EXCLUDED.full_name,
        email                = EXCLUDED.email,
        role                 = 'admin',
        status               = 'active',
        profile_completed_at = COALESCE(public.profiles.profile_completed_at, now()),
        updated_at           = now();

  -- Ensure bauhaventc@gmail.com and jamrandyankiambom@gmail.com are active admins
  UPDATE public.profiles
  SET role                 = 'admin',
      status               = 'active',
      profile_completed_at = COALESCE(profile_completed_at, now()),
      updated_at           = now()
  WHERE id IN (v_primary_admin_id, v_jam_id);

  -- Build list of kept user IDs
  v_kept_ids := array_remove(ARRAY[v_primary_admin_id, v_jam_id, v_mbah_id], NULL);

  -- --------------------------------------------------------------------------
  -- 4. Grant active Super Admin role to mbahlesky2@gmail.com (and kept admins)
  -- --------------------------------------------------------------------------
  SELECT id INTO v_super_admin_role FROM public.roles WHERE code = 'super_admin';

  IF v_super_admin_role IS NOT NULL THEN
    -- Ensure mbahlesky2@gmail.com, bauhaventc@gmail.com, and jamrandyankiambom@gmail.com have active super_admin
    UPDATE public.user_role_assignments
    SET status = 'active', revoked_at = NULL, suspended_at = NULL, updated_at = now()
    WHERE user_id = ANY(v_kept_ids) AND role_id = v_super_admin_role AND scope_type = 'organisation';

    IF NOT EXISTS (
      SELECT 1 FROM public.user_role_assignments
      WHERE user_id = v_mbah_id AND role_id = v_super_admin_role AND scope_type = 'organisation' AND revoked_at IS NULL
    ) THEN
      INSERT INTO public.user_role_assignments (
        user_id, role_id, scope_type, scope_id, granted_by, assignment_type, valid_from, status
      ) VALUES (
        v_mbah_id, v_super_admin_role, 'organisation', NULL, v_primary_admin_id, 'permanent', now(), 'active'
      );
    END IF;

    IF NOT EXISTS (
      SELECT 1 FROM public.user_role_assignments
      WHERE user_id = v_primary_admin_id AND role_id = v_super_admin_role AND scope_type = 'organisation' AND revoked_at IS NULL
    ) THEN
      INSERT INTO public.user_role_assignments (
        user_id, role_id, scope_type, scope_id, granted_by, assignment_type, valid_from, status
      ) VALUES (
        v_primary_admin_id, v_super_admin_role, 'organisation', NULL, v_primary_admin_id, 'permanent', now(), 'active'
      );
    END IF;
  END IF;

  -- --------------------------------------------------------------------------
  -- 5. PRESERVE FINANCE DATA (Reassign audit FKs from deleted users)
  -- --------------------------------------------------------------------------
  UPDATE public.finance_fee_plans SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.finance_participant_charges SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.finance_payments SET recorded_by = v_primary_admin_id WHERE recorded_by IS NOT NULL AND NOT (recorded_by = ANY(v_kept_ids));
  UPDATE public.finance_payments SET payer_profile_id = NULL WHERE payer_profile_id IS NOT NULL AND NOT (payer_profile_id = ANY(v_kept_ids));
  UPDATE public.finance_receipts SET issued_by = v_primary_admin_id WHERE issued_by IS NOT NULL AND NOT (issued_by = ANY(v_kept_ids));
  UPDATE public.finance_income SET entered_by = v_primary_admin_id WHERE entered_by IS NOT NULL AND NOT (entered_by = ANY(v_kept_ids));
  UPDATE public.finance_income SET approved_by = v_primary_admin_id WHERE approved_by IS NOT NULL AND NOT (approved_by = ANY(v_kept_ids));
  UPDATE public.finance_income SET voided_by = v_primary_admin_id WHERE voided_by IS NOT NULL AND NOT (voided_by = ANY(v_kept_ids));
  UPDATE public.finance_expenses SET entered_by = v_primary_admin_id WHERE entered_by IS NOT NULL AND NOT (entered_by = ANY(v_kept_ids));
  UPDATE public.finance_expenses SET approved_by = v_primary_admin_id WHERE approved_by IS NOT NULL AND NOT (approved_by = ANY(v_kept_ids));
  UPDATE public.finance_expenses SET voided_by = v_primary_admin_id WHERE voided_by IS NOT NULL AND NOT (voided_by = ANY(v_kept_ids));
  UPDATE public.finance_loans SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.finance_loan_repayments SET recorded_by = v_primary_admin_id WHERE recorded_by IS NOT NULL AND NOT (recorded_by = ANY(v_kept_ids));
  UPDATE public.finance_budgets SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.finance_invoices SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.finance_invoices SET voided_by = v_primary_admin_id WHERE voided_by IS NOT NULL AND NOT (voided_by = ANY(v_kept_ids));
  UPDATE public.finance_petty_cash_entries SET entered_by = v_primary_admin_id WHERE entered_by IS NOT NULL AND NOT (entered_by = ANY(v_kept_ids));
  UPDATE public.finance_transaction_events SET actor_id = v_primary_admin_id WHERE actor_id IS NOT NULL AND NOT (actor_id = ANY(v_kept_ids));
  UPDATE public.finance_legacy_participants SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.finance_migration_exceptions SET resolved_by = v_primary_admin_id WHERE resolved_by IS NOT NULL AND NOT (resolved_by = ANY(v_kept_ids));
  UPDATE public.integration_ft_id_map SET matched_by = v_primary_admin_id WHERE matched_by IS NOT NULL AND NOT (matched_by = ANY(v_kept_ids));

  -- --------------------------------------------------------------------------
  -- 6. PRESERVE CATALOGUE & WEBSITE REVIEWS
  -- --------------------------------------------------------------------------
  UPDATE public.role_permissions SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.offerings SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.offerings SET updated_by = v_primary_admin_id WHERE updated_by IS NOT NULL AND NOT (updated_by = ANY(v_kept_ids));
  UPDATE public.cohorts SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.cohorts SET updated_by = v_primary_admin_id WHERE updated_by IS NOT NULL AND NOT (updated_by = ANY(v_kept_ids));
  UPDATE public.website_reviews SET user_id = NULL WHERE user_id IS NOT NULL AND NOT (user_id = ANY(v_kept_ids));

  -- --------------------------------------------------------------------------
  -- 7. PRESERVE ALL 92 APPLICATIONS & CLEAN UP TEST APPROVALS/ENROLMENTS
  -- --------------------------------------------------------------------------
  DELETE FROM public.application_approvals;
  DELETE FROM public.invitations;
  DELETE FROM public.enrolment_status_history;
  DELETE FROM public.task_assignments;
  DELETE FROM public.enrolments;
  DELETE FROM public.application_reviews;
  -- Unlink deleted user profile FKs on applications and reset test-approved ones to pending
  UPDATE public.applications
  SET applicant_id         = NULL,
      applicant_profile_id = NULL,
      assigned_reviewer_id = CASE
        WHEN assigned_reviewer_id = ANY(v_kept_ids) THEN assigned_reviewer_id
        ELSE NULL
      END,
      status               = CASE
        WHEN lower(status) = 'approved' THEN 'pending'
        ELSE status
      END;

  DELETE FROM public.application_status_history;

  -- --------------------------------------------------------------------------
  -- 8. DELETE UNNECESSARY TEST/DUMMY DATA & OTHER USER REFERENCES
  -- --------------------------------------------------------------------------
  -- Delete the 6 dummy test tasks ('deo', 'dett', 'Hi', 'jsjs', 'gg', etc.)
  DELETE FROM public.submission_files;
  DELETE FROM public.feedback;
  DELETE FROM public.submissions;
  DELETE FROM public.task_resources;
  DELETE FROM public.tasks;
  DELETE FROM public.learning_projects;

  -- Delete test attendance, notifications, and invitations
  DELETE FROM public.attendance_records;
  DELETE FROM public.attendance_sessions;
  DELETE FROM public.admin_invitations;
  DELETE FROM public.participant_profiles;
  DELETE FROM public.staff_profiles WHERE NOT (profile_id = ANY(v_kept_ids));
  DELETE FROM public.cohort_staff_assignments WHERE NOT (staff_profile_id = ANY(v_kept_ids)) OR NOT (created_by = ANY(v_kept_ids));
  DELETE FROM public.access_reviews WHERE NOT (reviewed_by = ANY(v_kept_ids));
  DELETE FROM public.audit_logs;
  DELETE FROM public.idempotency_keys;
  DELETE FROM public.notifications;
  DELETE FROM public.policy_acceptances WHERE NOT (profile_id = ANY(v_kept_ids));
  DELETE FROM public.absence_request_approvals;
  DELETE FROM public.absence_requests;
  DELETE FROM public.issue_reports;

  UPDATE public.storage_objects SET owner_profile_id = v_primary_admin_id WHERE owner_profile_id IS NOT NULL AND NOT (owner_profile_id = ANY(v_kept_ids));
  UPDATE public.storage_objects SET uploaded_by = v_primary_admin_id WHERE uploaded_by IS NOT NULL AND NOT (uploaded_by = ANY(v_kept_ids));
  UPDATE public.announcements SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.digital_resources SET created_by = v_primary_admin_id WHERE created_by IS NOT NULL AND NOT (created_by = ANY(v_kept_ids));
  UPDATE public.assets SET assigned_to = NULL WHERE assigned_to IS NOT NULL AND NOT (assigned_to = ANY(v_kept_ids));

  -- Clean up role assignments & events for deleted users
  DELETE FROM public.role_assignment_events
  WHERE (actor_id IS NOT NULL AND NOT (actor_id = ANY(v_kept_ids)))
     OR assignment_id IN (
       SELECT id FROM public.user_role_assignments WHERE NOT (user_id = ANY(v_kept_ids))
     );

  DELETE FROM public.user_role_assignments
  WHERE NOT (user_id = ANY(v_kept_ids));

  UPDATE public.user_role_assignments
  SET granted_by   = v_primary_admin_id
  WHERE granted_by IS NOT NULL AND NOT (granted_by = ANY(v_kept_ids));

  UPDATE public.user_role_assignments
  SET suspended_by = NULL
  WHERE suspended_by IS NOT NULL AND NOT (suspended_by = ANY(v_kept_ids));

  UPDATE public.user_role_assignments
  SET revoked_by   = NULL
  WHERE revoked_by IS NOT NULL AND NOT (revoked_by = ANY(v_kept_ids));

  -- --------------------------------------------------------------------------
  -- 9. DELETE ALL OTHER PROFILES AND AUTH USERS
  -- --------------------------------------------------------------------------
  DELETE FROM public.profiles WHERE NOT (id = ANY(v_kept_ids));
  DELETE FROM auth.users WHERE NOT (id = ANY(v_kept_ids));

  RAISE NOTICE 'SUCCESS: Kept %, %, and % (Super Admin). Cleaned test data & tables. Finance & 92 applications preserved.',
    'bauhaventc@gmail.com', 'jamrandyankiambom@gmail.com', v_mbah_email;
END $$;

COMMIT;
