-- =========================================================
-- 013 — An Admin can create a working account directly
-- =========================================================
--
-- Adds `admin_create_account(...)`: name, email, password, role and optional program in,
-- an account that can sign in immediately out. No link to send, nothing for the person to
-- set up, no waiting.
--
-- **Why this exists.** Onboarding was invitation-only: fill a form, copy a link, deliver it
-- by hand (no mail provider is configured), and wait for the person to open it and choose a
-- password. That is the right flow for someone you are emailing. It is the wrong flow for
-- someone standing in front of you, and it was the *only* flow — the alternative was
-- `supabase/seed/002_seed_accounts.sql`, which needs a database credential and a SQL editor.
--
-- **What it costs, stated plainly.** The Admin chooses the password, so the Admin knows it.
-- That contradicts the principle the invitation path was built on and which
-- `Bauhaven-Core-Feature-Spec.md` states outright — "the invitee sets their own password;
-- nobody, including the Admin who invited them, ever sees or chooses it". Both paths now
-- exist because they answer different situations, and the trade is deliberate rather than
-- overlooked. The UI says so where an Admin can read it. Invitations remain the default.
--
-- ---------------------------------------------------------
-- How this differs from `seed_account`, and why it must
-- ---------------------------------------------------------
--
-- The body below is the same hard-won `auth.users` insert as `002_seed_accounts.sql` — the
-- empty-string token columns and the `auth.identities` row that a working sign-in needs, both
-- of which cost a round of "the account exists and cannot log in" to find. Three things are
-- deliberately different, because a seed script run by a DBA and an RPC reachable from a web
-- session are not the same object:
--
--   1. **It refuses an email that already exists. It never updates one.** `seed_account`
--      resets the password on re-run, which is what you want from a script you are iterating
--      on. Exposed over PostgREST, that same behaviour would let any Admin overwrite *any*
--      account's password — including another Admin's — and sign in as them, silently. That
--      is account takeover with an audit trail that reads like onboarding. Refusing is the
--      whole security boundary of this function.
--
--   2. **It is gated on `auth_is_admin()` before anything else.** `security definer` runs as
--      the owner, so without this check the `anon` key would create admins.
--
--   3. **It refuses an archived account**, rather than quietly reviving one. Somebody was
--      archived on purpose; un-archiving is a decision made in People, where the history is
--      visible, not a side effect of typing an email that happens to collide.

-- ---------------------------------------------------------
-- The function
-- ---------------------------------------------------------

create or replace function admin_create_account(
  p_email text,
  p_password text,
  p_name text,
  p_role text,
  -- Only meaningful for a learner role. Enrols them too, so Academy has something to show:
  -- a learner with no enrolment sits behind the pending gate looking at an application that
  -- does not exist.
  p_program_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public, auth, extensions, pg_temp as $$
declare
  v_user_id uuid;
  v_email text := lower(trim(p_email));
  v_name text := trim(p_name);
begin
  -- ---- Authorization, before anything else --------------------------------
  --
  -- Admin-only, matching `user_roles_write`. Staff keep the invitation path, which
  -- `invitations_insert` already limits to learner roles — the two paths stay exactly as
  -- powerful as each other, which is the rule 009 established when it closed the
  -- escalation in `invitations_admin_staff`.
  if not auth_is_admin() then
    raise exception 'Only an Admin can create an account directly.'
      using errcode = '42501';
  end if;

  if p_role not in ('admin','staff','intern','student','holiday_maker') then
    raise exception 'Unknown role %.', p_role using errcode = '22023';
  end if;

  if v_email is null or v_email !~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
    raise exception 'That does not look like an email address.' using errcode = '22023';
  end if;

  if v_name is null or length(v_name) < 2 then
    raise exception 'Enter the person''s name.' using errcode = '22023';
  end if;

  -- Eight, not Supabase Auth's minimum of six. An Admin typing a password on someone
  -- else's behalf will reach for something short, and this is the same floor Academy's
  -- own sign-up form applies.
  if p_password is null or length(p_password) < 8 then
    raise exception 'Use a password of at least 8 characters.' using errcode = '22023';
  end if;

  -- ---- Refuse, never overwrite -------------------------------------------
  --
  -- See point 1 in the header. This is the check that keeps the function from being an
  -- account-takeover tool. `auth.users.email` is not reliably unique across providers, so
  -- this is checked rather than left to a constraint.
  if exists (select 1 from auth.users where lower(email) = v_email) then
    raise exception 'An account already exists for %. Use People to change their roles, or the invitation flow to add a role.', v_email
      using errcode = '23505';
  end if;

  -- An archived person still holds the address. Reviving them here would skip the decision.
  if exists (select 1 from public.users where lower(email) = v_email and deleted_at is not null) then
    raise exception 'An archived account already uses %. Restore it from People instead.', v_email
      using errcode = '23505';
  end if;

  if p_program_id is not null and not exists (select 1 from programs where id = p_program_id) then
    raise exception 'That program does not exist.' using errcode = '23503';
  end if;

  -- ---- Create it ----------------------------------------------------------
  v_user_id := gen_random_uuid();

  insert into auth.users (
    instance_id, id, aud, role, email, encrypted_password,
    -- There is no inbox to confirm from — an Admin is vouching for this person in
    -- person. Left null, the account exists and cannot sign in whenever email
    -- confirmation is switched on, which it is.
    email_confirmed_at,
    -- **Empty strings, not NULL.** GoTrue reads these into non-nullable Go strings, so a
    -- NULL makes the row fail to load *before* the password is ever checked: sign-in fails
    -- with "Database error querying schema" while the account looks perfectly healthy in
    -- the dashboard. This cost a debugging round once already — see 002 and 004.
    confirmation_token, recovery_token, email_change, email_change_token_new,
    raw_app_meta_data, raw_user_meta_data, created_at, updated_at
  ) values (
    '00000000-0000-0000-0000-000000000000',
    v_user_id,
    'authenticated',
    'authenticated',
    v_email,
    -- bcrypt, the algorithm GoTrue checks against.
    crypt(p_password, gen_salt('bf')),
    now(),
    '', '', '', '',
    '{"provider":"email","providers":["email"]}'::jsonb,
    jsonb_build_object('name', v_name),
    now(),
    now()
  );

  -- **The row people forget.** GoTrue resolves an email/password sign-in through an
  -- identity; an `auth.users` row on its own is an account that exists, appears in the
  -- dashboard, and cannot log in.
  insert into auth.identities (
    provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) values (
    v_user_id::text,
    v_user_id,
    jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
    'email',
    now(), now(), now()
  );

  -- `handle_new_user()` fired on the insert above and created this row from
  -- `raw_user_meta_data`. Written defensively anyway: a database restored from a partial
  -- dump may not carry the trigger.
  insert into public.users (id, name, email)
  select v_user_id, v_name, v_email
  where not exists (select 1 from public.users where id = v_user_id);

  update public.users set name = v_name, email = v_email where id = v_user_id;

  -- No unique constraint on (user_id, role), so guarded rather than upserted.
  insert into user_roles (user_id, role, program_id, status)
  values (v_user_id, p_role, p_program_id, 'active');

  if p_program_id is not null and p_role in ('intern','student','holiday_maker') then
    insert into enrollments (user_id, program_id, status)
    values (v_user_id, p_program_id, 'active')
    on conflict (user_id, program_id) do nothing;
  end if;

  return v_user_id;
end;
$$;

-- `anon` must never reach this: `security definer` runs as the owner, and the
-- `auth_is_admin()` check inside returns false rather than raising for a signed-out
-- caller — but revoking is the boundary that does not depend on reading the body
-- correctly.
revoke all on function admin_create_account(text, text, text, text, uuid) from public, anon;
grant execute on function admin_create_account(text, text, text, text, uuid) to authenticated;

comment on function admin_create_account(text, text, text, text, uuid) is
  'Admin-only. Creates a signed-in-ready account with a password the Admin chooses. Refuses an email that already exists — it never updates one, because that would be account takeover. Prefer the invitation flow, where only the invitee ever knows the password.';
