-- =========================================================
-- 014 — Notifications that something actually creates
-- =========================================================
--
-- `notifications` has been in `001_initial_schema.sql` from the start with a SELECT policy,
-- an UPDATE policy, an index — and **no way for a row to ever exist**. There is no INSERT
-- policy, nothing in either app writes one, and no trigger produces one. Core feature #10
-- ("Notifications: system-generated — deadlines, approvals") has been unimplementable in
-- the same way `submissions.grade` was unwritable before 004 and `requests` couldn't leave
-- 'pending' before 008. Same shape of gap, found the same way: by trying to build on it.
--
-- ---------------------------------------------------------
-- Why triggers, and why still no INSERT policy
-- ---------------------------------------------------------
--
-- **A notification is a fact about an event, so it is written where the event is.** Two
-- apps, plus SQL scripts, can approve a request or assign a task; putting the insert in
-- Server Action code means every one of those paths has to remember, and the one that
-- forgets fails silently — the person just never hears. `006_submission_marks_task_submitted.sql`
-- made this exact call for the same reason.
--
-- **There is deliberately still no INSERT policy.** These trigger functions are
-- `security definer`, so they bypass RLS entirely and need none. Leaving it absent means
-- no signed-in user can write a notification by any route — which matters, because an
-- INSERT policy loose enough to let the app notify *somebody else* is one that lets any
-- account fabricate a message from Bauhaven in another person's list. The only writer is
-- the database itself, reacting to something that really happened.
--
-- ---------------------------------------------------------
-- The UPDATE policy was too wide
-- ---------------------------------------------------------
--
-- `notifications_update_own` is `for update using (user_id = auth.uid())` with no
-- `WITH CHECK` and no column list, so somebody could rewrite their own notification's
-- `type` and `payload` — or reassign it to another user — rather than only marking it read.
-- Nothing does that today; the policy simply permits it. Same class of finding as
-- `003_application_approval_rls.sql`, where `USING` without `WITH CHECK` let Staff write
-- `status = 'approved'`. Marking something read is the only thing a recipient needs to do.

-- ---------------------------------------------------------
-- Narrow the update to "mark as read"
-- ---------------------------------------------------------

drop policy if exists notifications_update_own on notifications;

-- Column-level: even with the policy below, no other column is writable by a client.
revoke update on notifications from anon, authenticated;
grant update (read_at) on notifications to authenticated;

create policy notifications_update_own on notifications for update
  using (user_id = auth.uid())
  -- Without this, the row could be handed to somebody else on the way out.
  with check (user_id = auth.uid());

-- ---------------------------------------------------------
-- The one function every trigger goes through
-- ---------------------------------------------------------

/**
 * Writes one notification.
 *
 * `payload` is deliberately **self-contained**: it carries the text the list needs to
 * render, not just an id to go and look up. Two reasons. A notification about a task that
 * was later archived, or a request from a programme somebody has since left, should still
 * read correctly — it is a record of what happened, not a live view. And rendering a list
 * of twenty notifications must not become twenty joins across tables whose RLS may no
 * longer let the reader see the row at all.
 */
create or replace function notify_user(
  p_user_id uuid,
  p_type text,
  p_payload jsonb
)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- Nobody is notified about their own action. Staff marking their own attendance, an
  -- Admin approving an application they filed — the person already knows, and a
  -- notification about something you just did reads as a bug.
  if p_user_id is null or p_user_id = auth.uid() then
    return;
  end if;

  insert into notifications (user_id, type, payload)
  values (p_user_id, p_type, p_payload);
end;
$$;

-- ---------------------------------------------------------
-- Task assigned
-- ---------------------------------------------------------

create or replace function notify_task_assigned()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  -- On insert, or when a task is reassigned to somebody new. `is distinct from` rather
  -- than `<>` because either side can be null — an unassigned task is the normal
  -- starting state, and `null <> x` is null, which would silently skip the notification.
  if TG_OP = 'INSERT' or NEW.assigned_to is distinct from OLD.assigned_to then
    perform notify_user(
      NEW.assigned_to,
      'task_assigned',
      jsonb_build_object('task_id', NEW.id, 'title', NEW.title, 'deadline', NEW.deadline)
    );
  end if;

  return NEW;
end;
$$;

create trigger trg_notify_task_assigned
  after insert or update of assigned_to on tasks
  for each row execute function notify_task_assigned();

-- ---------------------------------------------------------
-- Work graded
-- ---------------------------------------------------------

create or replace function notify_submission_graded()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if NEW.grade is not null and NEW.grade is distinct from OLD.grade then
    perform notify_user(
      NEW.user_id,
      'submission_graded',
      jsonb_build_object(
        'submission_id', NEW.id,
        'task_id', NEW.task_id,
        'grade', NEW.grade,
        'title', (select t.title from tasks t where t.id = NEW.task_id)
      )
    );
  end if;

  return NEW;
end;
$$;

create trigger trg_notify_submission_graded
  after update of grade on submissions
  for each row execute function notify_submission_graded();

-- ---------------------------------------------------------
-- Feedback left on somebody's work
-- ---------------------------------------------------------
--
-- Separate from grading on purpose: they're two different rows written at two different
-- times, and `Bauhaven-Database-Schema.md` ("Where a grade lives") is explicit that
-- `feedback` is a comment with an optional 1-5 rating that is *not* the grade.

create or replace function notify_feedback_left()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_owner uuid;
  v_task_id uuid;
begin
  select s.user_id, s.task_id into v_owner, v_task_id
  from submissions s where s.id = NEW.submission_id;

  perform notify_user(
    v_owner,
    'feedback_received',
    jsonb_build_object(
      'submission_id', NEW.submission_id,
      'task_id', v_task_id,
      'title', (select t.title from tasks t where t.id = v_task_id)
    )
  );

  return NEW;
end;
$$;

create trigger trg_notify_feedback_left
  after insert on feedback
  for each row execute function notify_feedback_left();

-- ---------------------------------------------------------
-- Absence request decided
-- ---------------------------------------------------------

create or replace function notify_request_decided()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if NEW.status is distinct from OLD.status and NEW.status in ('approved', 'rejected') then
    perform notify_user(
      NEW.requester_id,
      'request_decided',
      jsonb_build_object(
        'request_id', NEW.id,
        'status', NEW.status,
        'start_date', NEW.start_date,
        'end_date', NEW.end_date
      )
    );
  end if;

  return NEW;
end;
$$;

create trigger trg_notify_request_decided
  after update of status on requests
  for each row execute function notify_request_decided();

-- ---------------------------------------------------------
-- Application decided
-- ---------------------------------------------------------
--
-- Only when there is an account to notify. An anonymous application from the public
-- website has `applicant_id` null (012) and is answered with an invitation instead —
-- `notify_user` returns early on a null recipient, so this needs no branch of its own.

create or replace function notify_application_decided()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if NEW.status is distinct from OLD.status and NEW.status in ('approved', 'declined') then
    perform notify_user(
      NEW.applicant_id,
      'application_decided',
      jsonb_build_object('application_id', NEW.id, 'status', NEW.status)
    );
  end if;

  return NEW;
end;
$$;

create trigger trg_notify_application_decided
  after update of status on applications
  for each row execute function notify_application_decided();

-- ---------------------------------------------------------
-- Issue report resolved
-- ---------------------------------------------------------

create or replace function notify_issue_resolved()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if NEW.status is distinct from OLD.status and NEW.status in ('in_progress', 'resolved') then
    perform notify_user(
      NEW.reporter_id,
      'issue_updated',
      jsonb_build_object(
        'issue_id', NEW.id,
        'status', NEW.status,
        'category', NEW.category
      )
    );
  end if;

  return NEW;
end;
$$;

create trigger trg_notify_issue_resolved
  after update of status on issue_reports
  for each row execute function notify_issue_resolved();

-- ---------------------------------------------------------
-- Work submitted — the one that goes to Staff
-- ---------------------------------------------------------
--
-- Every other trigger here has one obvious recipient. This one goes to whoever created the
-- task, which is the closest thing the schema has to "the person waiting on this".
--
-- **Deliberately not fanned out to all Staff.** "A new application arrived" or "a request
-- needs approval" would have to notify a group, and the schema has no way to say which
-- group: `user_roles.program_id` scopes a staff member to a programme with no reverse
-- lookup, and the request quorum resolves to "one Staff approval", not to a named person.
-- Notifying every Admin and every Staff member on every event is how a notification list
-- becomes something people stop opening. Left out until there is a rule worth encoding —
-- the same reasoning that kept issue-report category routing out of 001.

create or replace function notify_submission_received()
returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  perform notify_user(
    (select t.created_by from tasks t where t.id = NEW.task_id),
    'submission_received',
    jsonb_build_object(
      'submission_id', NEW.id,
      'task_id', NEW.task_id,
      'title', (select t.title from tasks t where t.id = NEW.task_id)
    )
  );

  return NEW;
end;
$$;

create trigger trg_notify_submission_received
  after insert on submissions
  for each row execute function notify_submission_received();

-- ---------------------------------------------------------
-- Web push subscriptions
-- ---------------------------------------------------------
--
-- One row per browser or installed app a person has allowed push on — genuinely per
-- device, not per account: somebody signs in on a shared phone and their own laptop, and
-- revoking one must not silence the other.
--
-- `endpoint` is unique across the whole table rather than per user. The push service issues
-- it, and it identifies a browser install, not a person — so if a device is handed to
-- somebody else and they subscribe, the row must move to the new owner rather than
-- duplicate. That's what the upsert in the app relies on.

create table if not exists push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references users(id) on delete cascade,
  endpoint text not null unique,
  -- The two halves of the browser's public key, exactly as `PushSubscription.toJSON()`
  -- reports them. Stored as given: they're opaque to us and re-encoding them is a way to
  -- break delivery for reasons nobody can see.
  p256dh text not null,
  auth text not null,
  -- Which app the subscription came from, so a send can target one. Push permission is
  -- per-origin, so a person using both apps has two subscriptions and they are not
  -- interchangeable.
  app text not null default 'academy' check (app in ('academy', 'admin')),
  created_at timestamptz not null default now(),
  last_used_at timestamptz
);

create index if not exists idx_push_subscriptions_user on push_subscriptions (user_id);

alter table push_subscriptions enable row level security;

-- Somebody manages their own subscriptions and nobody else's. There is no read policy for
-- Staff or Admin: a push endpoint is a capability — anyone holding it can send to that
-- device — so the fewer readers, the better. The sender runs with a service credential
-- outside RLS.
create policy push_subscriptions_select_own on push_subscriptions for select
  using (user_id = auth.uid());

create policy push_subscriptions_insert_own on push_subscriptions for insert
  with check (user_id = auth.uid());

create policy push_subscriptions_update_own on push_subscriptions for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy push_subscriptions_delete_own on push_subscriptions for delete
  using (user_id = auth.uid());

comment on table push_subscriptions is
  'One row per browser/device a person has allowed push on. `endpoint` is unique table-wide because it identifies a browser install rather than a person — a re-subscribe on a handed-down device moves the row instead of duplicating it.';
