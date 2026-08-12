-- =========================================================
-- Bootstrap: the first Admin
-- =========================================================
--
-- **Run this once, by hand, on a fresh database. Nothing else in the platform needs it.**
--
-- There is a deliberate chicken-and-egg in the authorization model: `user_roles_write` is
-- `using (auth_is_admin())`, so only an existing Admin can grant a role. That is the
-- correct rule — it's what stops anyone promoting themselves — but it means the *first*
-- Admin cannot be created through either app, through the API, or through an invitation.
-- Somebody has to insert that first row with a credential that bypasses RLS.
--
-- Every account after this one goes through Invitations (`009_invitations_and_onboarding.sql`)
-- and Admin-web's Users screen. This script exists so the one unavoidable manual step is a
-- known, reviewed, repeatable thing rather than tribal knowledge.
--
-- ---------------------------------------------------------
-- How to run it
-- ---------------------------------------------------------
--
--   1. Create the auth account first — this script does not create it, on purpose.
--      Passwords belong to Supabase Auth's own hashing, not to a SQL file in a repo.
--
--        Supabase Dashboard → Authentication → Users → Add user
--        (or)  supabase auth admin create-user --email founder@bauhaven.com
--
--      `handle_new_user()` fires on that insert and creates the matching `public.users`
--      row automatically, so there is nothing to do there either.
--
--   2. Set the email below and run this in the SQL editor, or:
--
--        psql "$DATABASE_URL" -v email="'founder@bauhaven.com'" -f supabase/seed/001_first_admin.sql
--
--   3. Sign in to Admin-web. Everything else — inviting the second Admin, Staff, and
--      students — happens in the app from here.
--
-- Safe to re-run: it grants nothing twice and fails loudly if the account doesn't exist.

do $$
declare
  -- ⬇︎ CHANGE THIS, or pass -v email='...' on the command line.
  v_email text := coalesce(current_setting('bauhaven.first_admin_email', true), 'founder@bauhaven.com');
  v_user_id uuid;
begin
  select id into v_user_id from auth.users where lower(email) = lower(v_email);

  if v_user_id is null then
    -- Loud rather than silent: a seed that quietly does nothing is how someone spends an
    -- afternoon wondering why they can't sign in.
    raise exception
      'No auth user for %. Create the account in Supabase Auth first (step 1 above), then re-run.',
      v_email;
  end if;

  -- `handle_new_user()` should already have made this row. Covered anyway, because a
  -- database restored from a partial dump may not have it and the FK below needs it.
  insert into public.users (id, name, email)
  select v_user_id, split_part(v_email, '@', 1), v_email
  where not exists (select 1 from public.users where id = v_user_id);

  if exists (
    select 1 from user_roles
    where user_id = v_user_id and role = 'admin' and status = 'active'
  ) then
    raise notice '% is already an active Admin — nothing to do.', v_email;
    return;
  end if;

  insert into user_roles (user_id, role, status) values (v_user_id, 'admin', 'active');

  raise notice 'Granted Admin to %. Sign in to Admin-web and invite everyone else from Users.', v_email;
end $$;
