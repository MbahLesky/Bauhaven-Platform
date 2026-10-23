-- =========================================================
-- Invitations: the only non-manual path to an account
-- =========================================================
--
-- Before this migration there was **no way to create an account except by hand** — in
-- either app, for anyone. Neither client has a signup route, `handle_new_user()` fills in
-- `public.users` but nothing grants a role, and `user_roles_write` is
-- `using (auth_is_admin())`, so a brand-new user cannot give themselves one and nobody
-- but an existing Admin can give them one either. Every account — the first Founder, every
-- Staff member, every student — required a Supabase dashboard visit plus a direct SQL
-- insert that bypasses RLS.
--
-- `invitations` has been in `001_initial_schema.sql` since the beginning with a policy but
-- no reader and no writer. This migration makes it work.
--
-- **No service-role key.** The accept flow runs as the invitee — anonymous first, then
-- authenticated — through two `security definer` functions, the same approach
-- `auth_has_permission` already uses. A service-role key in an app's environment is a
-- standing bypass of RLS on *every* table, and adding one so a single flow can write two
-- rows is a poor trade. These functions can do exactly two things and nothing else.

-- ---------------------------------------------------------
-- What an invitation needs to carry
-- ---------------------------------------------------------

-- An invitation issued from an approved application should land the person in the program
-- they applied to, and `invitations` had nowhere to record that. This is the missing half
-- of the "Application→Enrollment handoff" the Development Plan lists as deferred.
alter table invitations add column if not exists program_id uuid references programs(id);

-- Which application produced this invitation, when one did. Nullable: a Staff member
-- inviting a new mentor isn't acting on an application.
alter table invitations add column if not exists application_id uuid references applications(id);

-- The role has always been free text. Constrain it to what `user_roles.role` accepts, so
-- an invitation can't promise a role that then fails to be granted on redemption.
alter table invitations add constraint invitations_invited_role_valid
  check (invited_role in ('admin','staff','intern','student','holiday_maker'));

create index if not exists idx_invitations_email_pending
  on invitations (email) where accepted_at is null;

-- ---------------------------------------------------------
-- Who may invite whom
-- ---------------------------------------------------------

-- `invitations_admin_staff` was `for all using (auth_is_admin_or_staff())` — which let a
-- Staff member invite somebody as an **admin**, i.e. grant a role they cannot grant
-- directly. Privilege escalation through the side door. Replaced with policies that keep
-- the invitation path no more powerful than the direct one.
drop policy if exists invitations_admin_staff on invitations;

create policy invitations_select on invitations for select
  using (auth_is_admin_or_staff());

create policy invitations_insert on invitations for insert
  with check (
    invited_by = auth.uid()
    and (
      auth_is_admin()
      -- Staff may onboard learners. Creating Staff or Admins stays Admin's alone,
      -- matching `user_roles_write`.
      or (auth_is_staff() and invited_role in ('intern','student','holiday_maker'))
    )
  );

-- Revoking an unaccepted invitation is a delete; an accepted one is history and stays.
create policy invitations_delete on invitations for delete
  using (auth_is_admin_or_staff() and accepted_at is null);

-- ---------------------------------------------------------
-- Reading an invitation without being able to read the table
-- ---------------------------------------------------------

/**
 * What the accept screen shows before anyone has signed in.
 *
 * The invitee is anonymous at this point and `invitations_select` is Admin/Staff only, so
 * without this they could not see who invited them or what they're accepting. Returns the
 * email and role for a *valid* token only, and nothing at all otherwise — so it can't be
 * used to enumerate invitations or confirm that an address was invited.
 */
create or replace function invitation_preview(p_token text)
returns table (email text, invited_role text, program_id uuid)
language sql stable security definer set search_path = public, pg_temp as $$
  select i.email, i.invited_role, i.program_id
  from invitations i
  where i.token = p_token
    and i.accepted_at is null
    and i.expires_at > now();
$$;

revoke all on function invitation_preview(text) from public;
grant execute on function invitation_preview(text) to anon, authenticated;

/**
 * Turns a signed-in account into a member with a role.
 *
 * Called immediately after `supabase.auth.signUp`, as the new user. Grants the role the
 * invitation names, enrolls them if it carries a program, and marks the invitation used.
 *
 * **The role comes from the invitation, never from the caller** — that's the whole point.
 * An Admin or Staff member decided it when they issued the invite, subject to
 * `invitations_insert` above; the invitee only proves they hold the token and the address.
 *
 * The email check is what stops a leaked token being redeemed by whoever finds it: the
 * signed-in account's address must match the address the invitation was issued to.
 *
 * Idempotent by way of the `accepted_at is null` guard — a double-submitted form or a
 * refreshed tab redeems once and reports false the second time.
 */
create or replace function redeem_invitation(p_token text)
returns boolean
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_invitation invitations%rowtype;
  v_email text;
begin
  if auth.uid() is null then
    return false;
  end if;

  select email into v_email from auth.users where id = auth.uid();

  select * into v_invitation
  from invitations
  where token = p_token
    and accepted_at is null
    and expires_at > now()
    -- Case-insensitive: an invitation sent to Sam@example.com is the same person who
    -- signs up as sam@example.com, and refusing that would look like a broken link.
    and lower(email) = lower(v_email)
  for update;

  if not found then
    return false;
  end if;

  -- `unique (user_id, role)` isn't on this table, so re-granting is guarded here.
  insert into user_roles (user_id, role, program_id, status)
  select auth.uid(), v_invitation.invited_role, v_invitation.program_id, 'active'
  where not exists (
    select 1 from user_roles ur
    where ur.user_id = auth.uid()
      and ur.role = v_invitation.invited_role
      and ur.status = 'active'
  );

  -- An invitation carrying a program enrolls them in it. This is what makes an approved
  -- application become a student rather than just an account.
  if v_invitation.program_id is not null
     and v_invitation.invited_role in ('intern','student','holiday_maker') then
    insert into enrollments (user_id, program_id, status)
    select auth.uid(), v_invitation.program_id, 'active'
    where not exists (
      select 1 from enrollments e
      where e.user_id = auth.uid() and e.program_id = v_invitation.program_id
    );
  end if;

  update invitations set accepted_at = now() where id = v_invitation.id;

  return true;
end;
$$;

revoke all on function redeem_invitation(text) from public;
grant execute on function redeem_invitation(text) to authenticated;

-- ---------------------------------------------------------
-- User administration
-- ---------------------------------------------------------

-- `users_update_own` already allows `id = auth.uid() or auth_is_admin()`, which covers an
-- Admin editing or archiving (soft-deleting) an account. Staff get read access only —
-- `users_select_own` already grants it — so the Users screen shows Staff the directory
-- without the ability to change anyone.
--
-- `user_roles_write` stays `auth_is_admin()`: granting and revoking roles is Admin's, and
-- the invitation path above is deliberately no more permissive than it.
