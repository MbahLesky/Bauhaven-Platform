-- =========================================================
-- Hard-remove accounts — undoes 002_seed_accounts.sql
-- =========================================================
--
-- **This deletes. There is no undo, and no soft-delete fallback.** It removes the auth
-- user, the identity, the `public.users` row, every role, and everything the person owns:
-- their attendance records, submissions, requests, testimonies, issue reports, enrolments.
--
-- **For real people, this is almost never what you want.** Archiving — the People screen's
-- "Archive account", which stamps `users.deleted_at` — disables sign-in while keeping the
-- history that references them intact. That's the Core spec's stated intent ("soft delete,
-- not hard delete") and it's right: a student's attendance record is also the register's
-- record of that session, and a mentor's feedback is also the student's feedback.
--
-- Use this for seeded, demo and test accounts, on a database where losing their data is
-- the point.
--
--   psql "$DATABASE_URL" -f supabase/seed/003_remove_accounts.sql
--
-- Needs a credential that bypasses RLS — the Supabase SQL editor, or the connection string
-- from Project Settings → Database.
--
-- ---------------------------------------------------------
-- Why this is more than "delete from auth.users"
-- ---------------------------------------------------------
--
-- 24 foreign-key columns across 21 tables point at `public.users`, and **only three
-- cascade** (`user_roles`, `notifications`, `user_permission_overrides.user_id`). Every
-- other one blocks the delete outright, so a bare `delete` fails on the first table it
-- meets and tells you nothing useful about the rest.
--
-- The 21 split three ways, and the split is the whole design:
--
--   1. **Owned by them** — attendance records, submissions, requests, testimonies, issue
--      reports, enrolments, their own approval rows. Deleted with the account.
--
--   2. **Merely referencing them** on a nullable column — an application they reviewed, an
--      asset assigned to them, a finance record they approved. **Nulled, never deleted.**
--      Removing an application because its reviewer left would destroy somebody else's
--      record of their own application.
--
--   3. **Entangled with other people** on a NOT NULL column — an attendance *session* they
--      created (which holds the whole class's register for that day), a finance record they
--      recorded, feedback they wrote on a student's submission, a task they assigned to
--      someone else, a blog post, an announcement. There is no way to delete the account
--      without destroying data that belongs to other people, so **this script refuses**
--      and tells you what's in the way. Archive them instead.

-- ---------------------------------------------------------
-- Dry run — always look first
-- ---------------------------------------------------------

create or replace function preview_account_removal(p_emails text[])
returns table (email text, item text, count bigint, effect text)
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_ids uuid[];
begin
  select array_agg(u.id) into v_ids
  from public.users u where lower(u.email) = any (select lower(unnest(p_emails)));

  if v_ids is null then
    return query select null::text, 'No matching accounts'::text, 0::bigint, 'nothing to do'::text;
    return;
  end if;

  return query
  with owned as (
    select 'attendance records' as item, count(*) from attendance_records where user_id = any(v_ids)
    union all select 'submissions', count(*) from submissions where user_id = any(v_ids)
    union all select 'absence requests', count(*) from requests where requester_id = any(v_ids)
    union all select 'approval rows', count(*) from request_approvals where approver_id = any(v_ids)
    union all select 'issue reports filed', count(*) from issue_reports where reporter_id = any(v_ids)
    union all select 'testimonies', count(*) from testimonies where user_id = any(v_ids)
    union all select 'enrolments', count(*) from enrollments where user_id = any(v_ids)
    union all select 'portfolio entries', count(*) from portfolio_entries where user_id = any(v_ids)
    union all select 'invitations they sent', count(*) from invitations where invited_by = any(v_ids)
    union all select 'roles', count(*) from user_roles where user_id = any(v_ids)
  ),
  nulled as (
    select 'applications they reviewed' as item, count(*) from applications where reviewed_by = any(v_ids)
    union all select 'assets assigned to them', count(*) from assets where assigned_to = any(v_ids)
    union all select 'tasks assigned to them', count(*) from tasks where assigned_to = any(v_ids)
    union all select 'issue reports they resolved', count(*) from issue_reports where resolved_by = any(v_ids)
    union all select 'finance records they approved', count(*) from finance_records where approved_by = any(v_ids)
    union all select 'finance records they paid', count(*) from finance_records where payer_id = any(v_ids)
    union all select 'blogs they approved', count(*) from blogs where approved_by = any(v_ids)
  ),
  blocking as (
    select 'attendance SESSIONS they created' as item, count(*) from attendance_sessions where created_by = any(v_ids)
    union all select 'finance records they recorded', count(*) from finance_records where recorded_by = any(v_ids)
    union all select 'feedback they wrote', count(*) from feedback where author_id = any(v_ids)
    union all select 'tasks they created', count(*) from tasks where created_by = any(v_ids)
    union all select 'projects they created', count(*) from projects where created_by = any(v_ids)
    union all select 'blogs they wrote', count(*) from blogs where author_id = any(v_ids)
    union all select 'announcements they posted', count(*) from announcements where author_id = any(v_ids)
    union all select 'permission grants they made', count(*) from user_permission_overrides where granted_by = any(v_ids)
  )
  select null::text, o.item, o.count, 'DELETED with the account' from owned o where o.count > 0
  union all
  select null::text, n.item, n.count, 'kept, reference set to null' from nulled n where n.count > 0
  union all
  select null::text, b.item, b.count, '*** BLOCKS REMOVAL — archive instead ***' from blocking b where b.count > 0
  order by 4, 2;
end;
$$;

-- ---------------------------------------------------------
-- The removal
-- ---------------------------------------------------------

create or replace function remove_account(
  p_email text,
  -- Escape hatch for a full teardown — removing every seeded account *includes* the only
  -- Admin, and the guard below would otherwise make that impossible. Off by default,
  -- because on a live database losing the last Admin is exactly what you want stopped.
  p_allow_last_admin boolean default false
)
returns boolean
language plpgsql security definer set search_path = public, auth, pg_temp as $$
declare
  v_id uuid;
  v_email text := lower(trim(p_email));
  v_blockers text;
  v_admins_left integer;
begin
  select id into v_id from public.users where lower(email) = v_email;

  if v_id is null then
    raise notice 'No account for % — nothing to remove.', v_email;
    return false;
  end if;

  -- Entangled with other people's data. Listed rather than counted, so the message says
  -- what to go and look at.
  select string_agg(label || ' (' || n || ')', ', ') into v_blockers
  from (
    select 'attendance sessions they created' as label, count(*) n from attendance_sessions where created_by = v_id
    union all select 'finance records they recorded', count(*) from finance_records where recorded_by = v_id
    union all select 'feedback they wrote', count(*) from feedback where author_id = v_id
    union all select 'tasks they created', count(*) from tasks where created_by = v_id
    union all select 'projects they created', count(*) from projects where created_by = v_id
    union all select 'blogs they wrote', count(*) from blogs where author_id = v_id
    union all select 'announcements they posted', count(*) from announcements where author_id = v_id
    union all select 'permission grants they made', count(*) from user_permission_overrides where granted_by = v_id
  ) t where n > 0;

  if v_blockers is not null then
    raise exception
      E'Cannot hard-remove % — they own data other people depend on: %.\n'
      'Deleting the account would destroy it (an attendance session holds the whole class''s '
      'register; feedback belongs to the student it was written for). Archive them instead: '
      'People → Archive account, or  update users set deleted_at = now() where id = ''%'';',
      v_email, v_blockers, v_id;
  end if;

  -- Removing the last Admin leaves nobody who can grant the role back through the app, and
  -- the fix is `001_first_admin.sql` plus a database credential. Same guard the People
  -- screen enforces, for the same reason.
  if exists (select 1 from user_roles where user_id = v_id and role = 'admin' and status = 'active') then
    select count(distinct user_id) into v_admins_left
    from user_roles
    where role = 'admin' and status = 'active' and user_id <> v_id;

    if v_admins_left = 0 and not p_allow_last_admin then
      raise exception
        E'Cannot remove % — they are the only active Admin. Removing them locks everyone out '
        'of role management, and getting back in needs 001_first_admin.sql and a database '
        'credential.\nIf that is genuinely what you want (a full teardown), call '
        'remove_account(''%'', true).',
        v_email, v_email;
    end if;
  end if;

  -- Nullable references: keep the row, forget the person. Deleting an application because
  -- its reviewer left would destroy somebody else's record of their own application.
  update applications    set reviewed_by = null where reviewed_by = v_id;
  update assets          set assigned_to = null where assigned_to = v_id;
  update tasks           set assigned_to = null where assigned_to = v_id;
  update issue_reports   set resolved_by = null, resolved_at = null where resolved_by = v_id;
  update finance_records set approved_by = null where approved_by = v_id;
  update finance_records set payer_id    = null where payer_id    = v_id;
  update blogs           set approved_by = null where approved_by = v_id;

  -- Owned rows, deepest first so nothing is orphaned on the way out.
  delete from feedback where submission_id in (select id from submissions where user_id = v_id);
  delete from submissions        where user_id      = v_id;
  delete from attendance_records where user_id      = v_id;
  delete from request_approvals  where approver_id  = v_id;
  delete from request_approvals  where request_id in (select id from requests where requester_id = v_id);
  delete from requests           where requester_id = v_id;
  delete from issue_reports      where reporter_id  = v_id;
  delete from testimonies        where user_id      = v_id;
  delete from portfolio_entries  where user_id      = v_id;
  delete from enrollments        where user_id      = v_id;
  delete from invitations        where invited_by   = v_id;
  -- Also any unaccepted invitation *to* this address, so re-seeding starts clean.
  delete from invitations        where lower(email) = v_email;
  delete from user_roles         where user_id      = v_id;

  -- `public.users.id` references `auth.users(id) on delete cascade`, and
  -- `auth.identities.user_id` cascades too — so this one statement removes all three.
  delete from auth.users where id = v_id;

  raise notice 'Removed % completely.', v_email;
  return true;
end;
$$;

-- ---------------------------------------------------------
-- 1. Look first
-- ---------------------------------------------------------
--
-- ⬇︎ EDIT THIS LIST. It matches the accounts 002_seed_accounts.sql creates.

select * from preview_account_removal(array[
  'founder@bauhaven.com',
  'admin2@bauhaven.com',
  'mentor@bauhaven.com',
  'auditor@bauhaven.com',
  'intern@bauhaven.com',
  'student@bauhaven.com'
]);

-- ---------------------------------------------------------
-- 2. Then remove
-- ---------------------------------------------------------
--
-- Read the preview above before running this. Anything marked "BLOCKS REMOVAL" will raise
-- and roll the whole block back — nothing is half-removed.

do $$
begin
  perform remove_account('student@bauhaven.com');
  perform remove_account('intern@bauhaven.com');
  perform remove_account('auditor@bauhaven.com');
  perform remove_account('mentor@bauhaven.com');
  perform remove_account('admin2@bauhaven.com');
  -- Last, and with the last-Admin guard explicitly waived: this is a teardown of every
  -- seeded account, so there is meant to be no Admin left afterwards. Getting back in then
  -- means running 001_first_admin.sql (or 002) again.
  perform remove_account('founder@bauhaven.com', true);
end $$;

-- ---------------------------------------------------------
-- 3. Confirm
-- ---------------------------------------------------------

select
  (select count(*) from auth.users)      as auth_users,
  (select count(*) from auth.identities) as identities,
  (select count(*) from public.users)    as app_users,
  (select count(*) from user_roles)      as roles,
  (select count(*) from enrollments)     as enrolments;

-- Tidy up the helpers, so they aren't left callable on a database you didn't mean them on.
-- Comment these out if you're iterating.
drop function if exists remove_account(text, boolean);
drop function if exists preview_account_removal(text[]);
