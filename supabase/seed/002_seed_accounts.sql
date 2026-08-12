-- =========================================================
-- Direct account seeding — accounts that can sign in immediately
-- =========================================================
--
-- **For bootstrapping, development and testing. Not the normal way to add people.**
--
-- The normal way is Admin-web's People screen: an Admin or Staff member invites by email,
-- the person opens the link and chooses their own password, and nobody else ever knows it.
-- Use that for real staff and real students.
--
-- This script exists for the cases invitations can't cover:
--
--   * the first Admin, before anyone can invite anyone (see also `001_first_admin.sql`);
--   * a development or staging database that needs a working set of accounts in one go;
--   * a demo, or a test run that shouldn't depend on clicking through an invite flow.
--
-- **What you give up by using it.** You choose the password, so you know it — meaning it's
-- in your shell history, your clipboard and possibly a chat message. That's fine for a
-- throwaway database and wrong for production. If you seed a production account this way,
-- treat the password as compromised and have the person change it.
--
-- **Run it with a credential that bypasses RLS** — the Supabase SQL editor, or psql with
-- the connection string from Project Settings → Database. The `anon` key cannot do this,
-- by design: writing `auth.users` and granting roles are exactly the things RLS prevents.
--
--   psql "$DATABASE_URL" -f supabase/seed/002_seed_accounts.sql
--
-- Running it twice is safe: existing accounts have their password and name updated rather
-- than being duplicated, and roles and enrolments are only added if missing.

-- ---------------------------------------------------------
-- The function
-- ---------------------------------------------------------

create or replace function seed_account(
  p_email text,
  p_password text,
  p_name text,
  p_role text,
  -- Only meaningful for intern/student/holiday_maker. Enrols them, so Academy has
  -- something to show — a learner with no enrolment sees empty screens everywhere.
  p_program_id uuid default null
)
returns uuid
language plpgsql security definer set search_path = public, auth, extensions, pg_temp as $$
declare
  v_user_id uuid;
  v_email text := lower(trim(p_email));
begin
  if p_role not in ('admin','staff','intern','student','holiday_maker') then
    raise exception 'Unknown role %. Use admin, staff, intern, student or holiday_maker.', p_role;
  end if;

  -- Supabase Auth's own minimum. Failing here beats creating an account that the sign-in
  -- form then refuses to accept a password for.
  if length(p_password) < 6 then
    raise exception 'Password for % is too short — Supabase Auth requires at least 6 characters.', v_email;
  end if;

  select id into v_user_id from auth.users where lower(email) = v_email;

  if v_user_id is null then
    v_user_id := gen_random_uuid();

    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      -- Set deliberately: with email confirmation switched on, an unconfirmed account
      -- cannot sign in, and a seeded account has no inbox to confirm from.
      email_confirmed_at,
      raw_app_meta_data, raw_user_meta_data, created_at, updated_at
    ) values (
      '00000000-0000-0000-0000-000000000000',
      v_user_id,
      'authenticated',
      'authenticated',
      v_email,
      -- bcrypt, the same algorithm GoTrue uses, so the sign-in check matches.
      crypt(p_password, gen_salt('bf')),
      now(),
      '{"provider":"email","providers":["email"]}'::jsonb,
      jsonb_build_object('name', p_name),
      now(),
      now()
    );

    -- **The row people forget.** Modern GoTrue looks up an identity to resolve an
    -- email/password sign-in; an `auth.users` row on its own produces an account that
    -- exists, appears in the dashboard, and cannot log in.
    insert into auth.identities (
      provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
    ) values (
      v_user_id::text,
      v_user_id,
      jsonb_build_object('sub', v_user_id::text, 'email', v_email, 'email_verified', true),
      'email',
      now(), now(), now()
    );
  else
    -- Re-running resets the password rather than failing, which is what you want from a
    -- seed script you're iterating on.
    update auth.users
    set encrypted_password = crypt(p_password, gen_salt('bf')),
        email_confirmed_at = coalesce(email_confirmed_at, now()),
        raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('name', p_name),
        updated_at = now()
    where id = v_user_id;
  end if;

  -- `handle_new_user()` creates this on insert. Covered anyway: it doesn't run on the
  -- update path above, and a database restored from a partial dump may be missing it.
  insert into public.users (id, name, email)
  select v_user_id, p_name, v_email
  where not exists (select 1 from public.users where id = v_user_id);

  update public.users
  set name = p_name, email = v_email, deleted_at = null
  where id = v_user_id;

  -- No unique constraint on (user_id, role), so this is guarded rather than upserted.
  insert into user_roles (user_id, role, program_id, status)
  select v_user_id, p_role, p_program_id, 'active'
  where not exists (
    select 1 from user_roles
    where user_id = v_user_id and role = p_role and status = 'active'
  );

  if p_program_id is not null and p_role in ('intern','student','holiday_maker') then
    -- `enrollments` has unique (user_id, program_id), so the conflict clause is enough.
    insert into enrollments (user_id, program_id, status)
    values (v_user_id, p_program_id, 'active')
    on conflict (user_id, program_id) do nothing;
  end if;

  raise notice '% (%) ready — sign in with the password you set.', v_email, p_role;

  return v_user_id;
end;
$$;

-- ---------------------------------------------------------
-- Seed some accounts
-- ---------------------------------------------------------
--
-- ⬇︎ EDIT THESE. Emails must be unique; passwords are yours to choose.
--
-- Which app each one signs into is decided by their role, not by the account:
--   admin, staff                     → Admin-web
--   intern, student, holiday_maker   → Academy-web
-- One account, one password, both apps — there is a single Supabase Auth instance behind
-- them (`Bauhaven-Architecture-Plan.md` §6). Someone holding both an Admin and an Intern
-- role can sign into either with the same credentials.

do $$
declare
  v_program_id uuid;
begin
  -- A program to enrol the learners on, so Academy isn't empty for them. Reuses one if
  -- the database already has any.
  select id into v_program_id from programs order by created_at limit 1;

  if v_program_id is null then
    insert into programs (type, title_en, description_en, duration_days, module_count)
    values ('program', 'Web Development Bootcamp', 'Seeded for development.', 84, 12)
    returning id into v_program_id;
  end if;

  -- Admins → Admin-web
  perform seed_account('founder@bauhaven.com',  'ChangeMe!2026', 'Bauhaven Founder', 'admin');
  perform seed_account('admin2@bauhaven.com',   'ChangeMe!2026', 'Second Founder',   'admin');

  -- Staff → Admin-web
  perform seed_account('mentor@bauhaven.com',   'ChangeMe!2026', 'Marc Mentor',      'staff');
  perform seed_account('auditor@bauhaven.com',  'ChangeMe!2026', 'Awa Auditor',      'staff');

  -- Learners → Academy-web, enrolled so their screens have content
  perform seed_account('intern@bauhaven.com',   'ChangeMe!2026', 'Ines Intern',      'intern',  v_program_id);
  perform seed_account('student@bauhaven.com',  'ChangeMe!2026', 'Sam Student',      'student', v_program_id);
end $$;

-- ---------------------------------------------------------
-- Check what you made
-- ---------------------------------------------------------

select
  u.email,
  u.name,
  string_agg(r.role, ', ' order by r.role) as roles,
  case
    when bool_or(r.role in ('admin','staff')) then 'Admin-web'
    else 'Academy-web'
  end as signs_into,
  (select count(*) from enrollments e where e.user_id = u.id and e.status = 'active') as enrolments
from public.users u
join user_roles r on r.user_id = u.id and r.status = 'active'
where u.deleted_at is null
group by u.id, u.email, u.name
order by u.email;
