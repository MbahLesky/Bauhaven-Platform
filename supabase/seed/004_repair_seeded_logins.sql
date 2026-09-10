-- =========================================================
-- Repair accounts created by 002 that can't sign in
-- =========================================================
--
-- **Symptom:** the account exists, shows up in Supabase → Authentication → Users, has the
-- right email, and signing in fails — often with "Database error querying schema", or a
-- generic invalid-credentials message. Meanwhile the very first Admin (created through the
-- dashboard rather than by SQL) signs in fine.
--
-- **Cause.** `auth.users` has several token columns that GoTrue reads into non-nullable Go
-- strings: `confirmation_token`, `recovery_token`, `email_change`, `email_change_token_new`,
-- `email_change_token_current`, `phone_change`, `phone_change_token`,
-- `reauthentication_token`. An account created through the dashboard or the API gets `''`
-- in all of them. `002_seed_accounts.sql` didn't name them, so on projects where those
-- columns have no default they were left `NULL` — and GoTrue cannot scan NULL into a
-- string, so the row fails to load *before* the password is ever checked. Nothing about
-- the account looks wrong, which is what makes it hard to spot.
--
-- The second thing this repairs is a missing `auth.identities` row. Modern GoTrue resolves
-- an email/password sign-in through the identity, so an `auth.users` row alone gives an
-- account that exists and cannot log in.
--
-- Run this once, with a credential that bypasses RLS. Safe to re-run, and safe on accounts
-- that were already fine — every fix is conditional.
--
--   psql "$DATABASE_URL" -f supabase/seed/004_repair_seeded_logins.sql

-- ---------------------------------------------------------
-- 1. Diagnose — what's actually wrong with each account
-- ---------------------------------------------------------

select
  u.email,
  case when u.encrypted_password is null then 'NO PASSWORD'
       when u.encrypted_password !~ '^\$2[aby]\$' then 'password not bcrypt'
       else 'password ok' end                                        as password,
  case when u.email_confirmed_at is null then 'NOT CONFIRMED — blocks sign-in'
       else 'confirmed' end                                          as confirmation,
  case when i.user_id is null then 'NO IDENTITY ROW — blocks sign-in'
       else 'identity ok' end                                        as identity,
  case when num_nulls(
              u.confirmation_token, u.recovery_token,
              u.email_change, u.email_change_token_new
            ) > 0
       then 'NULL TOKEN COLUMNS — blocks sign-in'
       else 'tokens ok' end                                          as token_columns,
  case when u.aud is distinct from 'authenticated'
         or u.role is distinct from 'authenticated'
       then 'aud/role wrong' else 'aud/role ok' end                   as audience
from auth.users u
left join auth.identities i on i.user_id = u.id and i.provider = 'email'
order by u.email;

-- ---------------------------------------------------------
-- 2. Repair
-- ---------------------------------------------------------

do $$
declare
  v_col text;
  v_fixed integer;
  -- Every column GoTrue scans as a non-nullable string. Driven by a loop rather than one
  -- big UPDATE because these columns have come and gone across Supabase versions — an
  -- older project may not have `reauthentication_token`, a newer one may add more. A
  -- missing column is skipped rather than raising.
  v_token_columns text[] := array[
    'confirmation_token',
    'recovery_token',
    'email_change',
    'email_change_token_new',
    'email_change_token_current',
    'phone_change',
    'phone_change_token',
    'reauthentication_token'
  ];
begin
  foreach v_col in array v_token_columns loop
    if exists (
      select 1 from information_schema.columns
      where table_schema = 'auth' and table_name = 'users' and column_name = v_col
    ) then
      execute format('update auth.users set %I = '''' where %I is null', v_col, v_col);
      get diagnostics v_fixed = row_count;
      if v_fixed > 0 then
        raise notice 'auth.users.%: set % NULL value(s) to empty string', v_col, v_fixed;
      end if;
    end if;
  end loop;

  -- An unconfirmed account cannot sign in when email confirmation is on, and a seeded
  -- account has no inbox to confirm from.
  update auth.users set email_confirmed_at = created_at
  where email_confirmed_at is null;
  get diagnostics v_fixed = row_count;
  if v_fixed > 0 then raise notice 'confirmed % account(s)', v_fixed; end if;

  -- GoTrue resolves an email/password sign-in through the identity row.
  insert into auth.identities (provider_id, user_id, identity_data, provider,
                               last_sign_in_at, created_at, updated_at)
  select u.id::text, u.id,
         jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
         'email', now(), now(), now()
  from auth.users u
  where u.email is not null
    and not exists (
      select 1 from auth.identities i where i.user_id = u.id and i.provider = 'email'
    );
  get diagnostics v_fixed = row_count;
  if v_fixed > 0 then raise notice 'created % missing identity row(s)', v_fixed; end if;

  -- Belt and braces: an account with the wrong audience is rejected before the password
  -- is checked.
  update auth.users set aud = 'authenticated' where aud is distinct from 'authenticated';
  update auth.users set role = 'authenticated' where role is distinct from 'authenticated';

  raise notice 'Repair complete. Re-run the query above — every column should read "ok".';
end $$;

-- ---------------------------------------------------------
-- 3. Confirm, and check a password while you're here
-- ---------------------------------------------------------
--
-- Replace the password with the one you seeded. `true` means GoTrue's own bcrypt check
-- will succeed — if this says true and sign-in still fails, the problem is no longer in
-- the database (check the app's SUPABASE_URL/ANON_KEY, and whether the project has email
-- confirmation or an allowlist enabled).

select
  u.email,
  (u.encrypted_password = crypt('ChangeMe!2026', u.encrypted_password)) as password_matches,
  u.email_confirmed_at is not null                                     as confirmed,
  exists (select 1 from auth.identities i
          where i.user_id = u.id and i.provider = 'email')             as has_identity,
  num_nulls(u.confirmation_token, u.recovery_token,
            u.email_change, u.email_change_token_new) = 0              as tokens_ok
from auth.users u
order by u.email;
