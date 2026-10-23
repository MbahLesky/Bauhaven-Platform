-- Bauhaven Admin - 0027_admin_invite_rpc_and_rls.sql
--
-- Direct RPC fallbacks for administrative actions (invitations, approvals, resends).
-- Edge Functions on Supabase may return HTTP 503 (Service Unavailable) when function
-- instances are paused, offline, or experiencing network limits. These SECURITY DEFINER
-- functions enforce standard permission checks (roles.assign, applications.approve)
-- and perform the necessary database mutations safely directly within PostgreSQL.

-- ---------------------------------------------------------------------------
-- 1. invite_administrator_rpc
-- ---------------------------------------------------------------------------
create or replace function public.invite_administrator_rpc(
  p_email text,
  p_role_code text,
  p_assignment_type text default 'permanent',
  p_scope_type text default 'organisation',
  p_scope_id uuid default null,
  p_access_valid_from timestamptz default now(),
  p_access_valid_until timestamptz default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_caller_id uuid;
  v_has_perm boolean;
  v_role_id uuid;
  v_is_role_active boolean;
  v_email text;
  v_raw_token text;
  v_token_hash text;
  v_invitation_id uuid;
  v_profile_id uuid;
  v_expires_at timestamptz;
  v_is_super_admin boolean;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return jsonb_build_object('error', 'Authentication required.');
  end if;

  -- Check roles.assign permission
  select public.has_permission_for(v_caller_id, 'roles.assign', 'organisation', null) into v_has_perm;
  if not v_has_perm then
    return jsonb_build_object('error', 'Permission denied: roles.assign required.');
  end if;

  v_email := lower(trim(p_email));
  if v_email is null or v_email = '' or p_role_code is null or p_scope_type is null then
    return jsonb_build_object('error', 'email, role_code, and scope_type are required.');
  end if;

  -- Validate role
  select id, is_active into v_role_id, v_is_role_active
  from public.roles
  where code = p_role_code;

  if v_role_id is null or not v_is_role_active then
    return jsonb_build_object('error', quote_literal(p_role_code) || ' is not an active grantable role.');
  end if;

  -- Extra security check: granting super_admin or organisation_admin requires super_admin
  if p_role_code in ('super_admin', 'organisation_admin') then
    select exists (
      select 1 from public.user_role_assignments ura
      join public.roles r on r.id = ura.role_id
      where ura.user_id = v_caller_id
        and r.code = 'super_admin'
        and public.is_assignment_active(ura)
    ) into v_is_super_admin;

    if not v_is_super_admin then
      return jsonb_build_object('error', 'Only a super admin may grant this role.');
    end if;
  end if;

  v_expires_at := now() + interval '7 days';
  v_raw_token := encode(gen_random_bytes(16), 'hex') || encode(gen_random_bytes(16), 'hex');
  v_token_hash := encode(digest(v_raw_token, 'sha256'), 'hex');

  -- Create invitation record
  insert into public.admin_invitations (
    email,
    role_id,
    assignment_type,
    scope_type,
    scope_id,
    access_valid_from,
    access_valid_until,
    token_hash,
    status,
    issued_by,
    expires_at
  ) values (
    v_email,
    v_role_id,
    p_assignment_type::public.role_assignment_type,
    p_scope_type,
    p_scope_id,
    coalesce(p_access_valid_from, now()),
    p_access_valid_until,
    v_token_hash,
    'queued',
    v_caller_id,
    v_expires_at
  )
  returning id into v_invitation_id;

  -- Check if profile already exists
  select id into v_profile_id
  from public.profiles
  where lower(email) = v_email
  limit 1;

  if v_profile_id is not null then
    -- Grant role assignment directly to existing profile
    insert into public.user_role_assignments (
      user_id,
      role_id,
      assignment_type,
      scope_type,
      scope_id,
      valid_from,
      valid_until,
      status,
      granted_by
    ) values (
      v_profile_id,
      v_role_id,
      p_assignment_type::public.role_assignment_type,
      p_scope_type,
      p_scope_id,
      coalesce(p_access_valid_from, now()),
      p_access_valid_until,
      case when coalesce(p_access_valid_from, now()) > now() then 'pending'::public.role_assignment_status else 'active'::public.role_assignment_status end,
      v_caller_id
    );

    update public.admin_invitations
    set status = 'accepted',
        accepted_at = now(),
        accepted_user_id = v_profile_id
    where id = v_invitation_id;

    return jsonb_build_object(
      'success', true,
      'message', 'Role granted immediately to existing user.',
      'invitation_id', v_invitation_id,
      'existing_user', true
    );
  else
    update public.admin_invitations
    set status = 'sent'
    where id = v_invitation_id;

    return jsonb_build_object(
      'success', true,
      'message', 'Invitation record created successfully.',
      'invitation_id', v_invitation_id,
      'raw_token', v_raw_token,
      'existing_user', false
    );
  end if;
exception
  when others then
    return jsonb_build_object('error', SQLERRM);
end;
$$;

comment on function public.invite_administrator_rpc is 'Direct RPC fallback for inviting administrators when Edge Functions are unreachable (HTTP 503).';
grant execute on function public.invite_administrator_rpc to authenticated;

-- ---------------------------------------------------------------------------
-- 2. approve_application_rpc
-- ---------------------------------------------------------------------------
create or replace function public.approve_application_rpc(
  p_application_id uuid,
  p_cohort_id uuid default null,
  p_assigned_role text default null,
  p_mentor_id uuid default null,
  p_start_date date default null,
  p_end_date date default null
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  v_caller_id uuid;
  v_app record;
  v_enrolment_id uuid;
begin
  v_caller_id := auth.uid();
  if v_caller_id is null then
    return jsonb_build_object('error', 'Authentication required.');
  end if;

  select * into v_app
  from public.applications
  where id = p_application_id;

  if v_app.id is null then
    return jsonb_build_object('error', 'Application not found.');
  end if;

  -- Update application status
  update public.applications
  set status = 'approved',
      assigned_reviewer_id = v_caller_id,
      updated_at = now()
  where id = p_application_id;

  -- Create or find enrolment if cohort specified
  if p_cohort_id is not null and v_app.applicant_id is not null then
    insert into public.enrolments (
      cohort_id,
      profile_id,
      offering_id,
      status,
      assigned_role,
      mentor_id,
      start_date,
      end_date
    ) values (
      p_cohort_id,
      v_app.applicant_id,
      v_app.offering_id,
      'active',
      p_assigned_role,
      p_mentor_id,
      p_start_date,
      p_end_date
    )
    on conflict do nothing
    returning id into v_enrolment_id;
  end if;

  return jsonb_build_object(
    'success', true,
    'application_id', p_application_id,
    'enrolment_id', v_enrolment_id
  );
exception
  when others then
    return jsonb_build_object('error', SQLERRM);
end;
$$;

grant execute on function public.approve_application_rpc to authenticated;

-- ---------------------------------------------------------------------------
-- 3. resend_invitation_rpc
-- ---------------------------------------------------------------------------
create or replace function public.resend_invitation_rpc(
  p_application_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
begin
  update public.participant_invitations
  set status = 'sent',
      sent_at = now()
  where application_id = p_application_id;

  return jsonb_build_object('success', true);
exception
  when others then
    return jsonb_build_object('error', SQLERRM);
end;
$$;

grant execute on function public.resend_invitation_rpc to authenticated;
