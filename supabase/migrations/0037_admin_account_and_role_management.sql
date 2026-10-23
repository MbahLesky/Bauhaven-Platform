-- =============================================================================
-- 0037_admin_account_and_role_management.sql (also referenced as proposed/08)
-- =============================================================================
-- 1. `public.admin_create_account(...)`: Lets an Admin create a working account
--    directly on the unified database (`auth.users`, `auth.identities`,
--    `public.profiles`, `public.user_role_assignments` for staff roles, and
--    `public.enrolments` for learners) without waiting on an invitation email.
--    Refuses existing emails (never overwrites) to prevent account takeover.
-- 2. `public.admin_revoke_role_assignment(...)`: Lets a Super Admin (`roles.revoke`)
--    revoke or suspend an active role assignment, while preventing revocation
--    of the last active Super Admin.
-- =============================================================================

create or replace function public.admin_create_account(
  p_email text,
  p_password text,
  p_name text,
  p_role_code text,
  p_scope_type text default 'organisation',
  p_scope_id uuid default null,
  p_offering_id uuid default null,
  p_cohort_id uuid default null,
  p_assigned_role text default 'Student'
)
returns uuid
language plpgsql
security definer
set search_path = public, private, auth, extensions, pg_temp
as $$
declare
  v_user_id uuid;
  v_role_id uuid;
  v_email text := lower(trim(p_email));
  v_name text := trim(p_name);
  v_caller_is_super_admin boolean;
begin
  -- Authorization check
  if not private.has_permission('roles.assign') and not public.is_admin(auth.uid()) then
    raise exception 'Only an Admin can create an account directly.'
      using errcode = '42501';
  end if;

  v_caller_is_super_admin := private.has_permission('roles.assign');
  if p_role_code = 'super_admin' and not v_caller_is_super_admin then
    raise exception 'Only a Super Admin can grant the Super Admin role.'
      using errcode = '42501';
  end if;

  if p_role_code <> 'learner' then
    select id into v_role_id
    from public.roles
    where code = p_role_code and is_active = true;

    if v_role_id is null then
      raise exception 'Unknown or inactive role %.', p_role_code
        using errcode = '22023';
    end if;
  else
    if p_offering_id is null or p_cohort_id is null then
      raise exception 'A learner account requires a programme and cohort.'
        using errcode = '22023';
    end if;
  end if;

  if v_email is null or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'That does not look like an email address.'
      using errcode = '22023';
  end if;

  if v_name is null or length(v_name) < 2 then
    raise exception 'Enter the person''s name.'
      using errcode = '22023';
  end if;

  if p_password is null or length(p_password) < 8 then
    raise exception 'Use a password of at least 8 characters.'
      using errcode = '22023';
  end if;

  if p_scope_type not in ('organisation', 'offering', 'cohort', 'project', 'content_domain', 'asset_domain') then
    raise exception 'Invalid scope type %.', p_scope_type
      using errcode = '22023';
  end if;

  if (p_scope_type = 'organisation' and p_scope_id is not null)
     or (p_scope_type <> 'organisation' and p_scope_id is null) then
    raise exception 'Scope ID must be provided if and only if scope is not organisation.'
      using errcode = '22023';
  end if;

  -- Refuse existing accounts (never overwrite passwords)
  if exists (select 1 from auth.users where lower(email) = v_email)
     or exists (select 1 from public.profiles where lower(email) = v_email) then
    raise exception 'An account already exists for %. Use the invitation flow to add a role to an existing account.', v_email
      using errcode = '23505';
  end if;

  if p_offering_id is not null and not exists (select 1 from public.offerings where id = p_offering_id) then
    raise exception 'That programme does not exist.'
      using errcode = '23503';
  end if;

  if p_cohort_id is not null and not exists (
    select 1 from public.cohorts
    where id = p_cohort_id
      and (p_offering_id is null or offering_id = p_offering_id)
  ) then
    raise exception 'That cohort does not belong to the chosen programme.'
      using errcode = '23503';
  end if;

  v_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    email_confirmed_at,
    confirmation_token, recovery_token, email_change, email_change_token_new,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
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

  insert into auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    v_user_id::text,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
    'email',
    now(), now(), now()
  );

  -- Ensure profile exists and is active
  insert into public.profiles (id, full_name, email, role, status)
  values (
    v_user_id,
    v_name,
    v_email,
    case when p_role_code = 'learner' then 'student' else 'admin' end,
    'active'
  )
  on conflict (id) do update
    set full_name = excluded.full_name,
        email = excluded.email,
        status = 'active',
        updated_at = now();

  -- Grant active role assignment for staff roles
  if v_role_id is not null then
    insert into public.user_role_assignments (
      user_id, role_id, scope_type, scope_id, granted_by,
      assignment_type, valid_from, status
    ) values (
      v_user_id, v_role_id, p_scope_type, p_scope_id, auth.uid(),
      'permanent', now(), 'active'
    );
  end if;

  -- Create active enrolment for learners
  if p_role_code = 'learner' and p_offering_id is not null and p_cohort_id is not null then
    insert into public.enrolments (
      profile_id, offering_id, cohort_id, assigned_role, status, activated_at, started_at
    ) values (
      v_user_id,
      p_offering_id,
      p_cohort_id,
      coalesce(nullif(trim(p_assigned_role), ''), 'Student'),
      'active',
      now(),
      current_date
    );
  end if;

  return v_user_id;
end;
$$;

revoke all on function public.admin_create_account(text, text, text, text, text, uuid, uuid, uuid, text) from public, anon;
grant execute on function public.admin_create_account(text, text, text, text, text, uuid, uuid, uuid, text) to authenticated;

-- Role revocation RPC for Super Admins (`roles.revoke`) -----------------------

create or replace function public.admin_revoke_role_assignment(
  p_assignment_id uuid,
  p_reason text default null
)
returns void
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_target public.user_role_assignments;
  v_role_code text;
  v_remaining_super_admins integer;
begin
  if not private.has_permission('roles.revoke') then
    raise exception 'Only a Super Admin can revoke a role assignment.'
      using errcode = '42501';
  end if;

  select * into v_target
  from public.user_role_assignments
  where id = p_assignment_id;

  if v_target.id is null then
    raise exception 'Role assignment not found.'
      using errcode = 'P0002';
  end if;

  if v_target.status = 'revoked' then
    return;
  end if;

  select code into v_role_code
  from public.roles
  where id = v_target.role_id;

  if v_role_code = 'super_admin' then
    select count(distinct ura.user_id) into v_remaining_super_admins
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    where r.code = 'super_admin'
      and ura.id <> p_assignment_id
      and public.is_assignment_active(ura);

    if coalesce(v_remaining_super_admins, 0) < 1 then
      raise exception 'Cannot revoke the last active Super Admin.'
        using errcode = '22023';
    end if;
  end if;

  update public.user_role_assignments
  set status = 'revoked',
      revoked_at = now(),
      revoked_by = auth.uid(),
      revocation_reason = nullif(trim(coalesce(p_reason, '')), ''),
      updated_at = now()
  where id = p_assignment_id;
end;
$$;

revoke all on function public.admin_revoke_role_assignment(uuid, text) from public, anon;
grant execute on function public.admin_revoke_role_assignment(uuid, text) to authenticated;
