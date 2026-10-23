-- =============================================================================
-- 0034_absence_requests_and_issue_reports.sql (also referenced as proposed/04)
-- =============================================================================
-- Adds `public.absence_requests`, `public.absence_request_approvals`, and
-- `public.issue_reports` for Bauhaven Academy and Bauhaven Admin.
--
-- Decision authority (`private.can_decide_absence_request`):
--   - Nobody may decide their own absence request.
--   - A learner's request (carries `enrolment_id`) is decided by staff holding
--     `participants.manage` for that enrolment's offering or cohort.
--   - A staff member's or Super Admin's request (`enrolment_id is null`) is
--     decided by holders of `roles.assign` (Super Admins).
-- =============================================================================

create table if not exists public.absence_requests (
  id           uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  enrolment_id uuid references public.enrolments(id) on delete set null,
  type         text not null default 'absence',
  start_date   date not null,
  end_date     date not null,
  reason       text,
  status       text not null default 'pending'
               check (status in ('pending', 'approved', 'rejected')),
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  check (end_date >= start_date)
);

create index if not exists absence_requests_requester_idx
  on public.absence_requests (requester_id, created_at desc);

create index if not exists absence_requests_status_idx
  on public.absence_requests (status, created_at asc);

create table if not exists public.absence_request_approvals (
  id          uuid primary key default gen_random_uuid(),
  request_id  uuid not null references public.absence_requests(id) on delete cascade,
  approver_id uuid not null references public.profiles(id) on delete cascade,
  decision    text check (decision in ('approved', 'rejected') or decision is null),
  decided_at  timestamptz,
  created_at  timestamptz not null default now(),
  unique (request_id, approver_id)
);

create index if not exists absence_request_approvals_request_idx
  on public.absence_request_approvals (request_id);

create table if not exists public.issue_reports (
  id          uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles(id) on delete cascade,
  category    text not null,
  description text not null,
  status      text not null default 'open'
              check (status in ('open', 'in_progress', 'resolved')),
  asset_id    uuid,
  offering_id uuid references public.offerings(id) on delete set null,
  resolved_by uuid references public.profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists issue_reports_reporter_idx
  on public.issue_reports (reporter_id, created_at desc);

create index if not exists issue_reports_status_idx
  on public.issue_reports (status, created_at desc);

-- updated_at triggers ---------------------------------------------------------

drop trigger if exists absence_requests_set_updated_at on public.absence_requests;
create trigger absence_requests_set_updated_at
  before update on public.absence_requests
  for each row execute function public.set_updated_at();

drop trigger if exists issue_reports_set_updated_at on public.issue_reports;
create trigger issue_reports_set_updated_at
  before update on public.issue_reports
  for each row execute function public.set_updated_at();

-- Helper functions ------------------------------------------------------------

create or replace function private.can_decide_absence_request(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.absence_requests ar
    left join public.enrolments e on e.id = ar.enrolment_id
    where ar.id = p_request_id
      and ar.requester_id <> auth.uid()
      and (
        (
          ar.enrolment_id is not null
          and (
            private.has_permission('participants.manage', 'offering', e.offering_id)
            or (e.cohort_id is not null and private.has_permission('participants.manage', 'cohort', e.cohort_id))
          )
        )
        or (
          ar.enrolment_id is null
          and private.has_permission('roles.assign')
        )
      )
  );
$$;

create or replace function private.can_see_absence_request(p_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.absence_requests ar
    where ar.id = p_request_id
      and (
        ar.requester_id = auth.uid()
        or public.is_admin(auth.uid())
        or private.can_decide_absence_request(ar.id)
      )
  );
$$;

revoke execute on function private.can_decide_absence_request(uuid) from public;
revoke execute on function private.can_see_absence_request(uuid) from public;
grant execute on function private.can_decide_absence_request(uuid) to authenticated, anon;
grant execute on function private.can_see_absence_request(uuid) to authenticated, anon;

-- Row Level Security ----------------------------------------------------------

alter table public.absence_requests enable row level security;
alter table public.absence_request_approvals enable row level security;
alter table public.issue_reports enable row level security;

drop policy if exists absence_requests_select on public.absence_requests;
create policy absence_requests_select on public.absence_requests
  for select
  using (
    requester_id = auth.uid()
    or public.is_admin(auth.uid())
    or private.can_decide_absence_request(id)
  );

drop policy if exists absence_requests_insert_own on public.absence_requests;
create policy absence_requests_insert_own on public.absence_requests
  for insert
  with check (
    requester_id = auth.uid()
    and status = 'pending'
    and (enrolment_id is null or private.owns_enrolment(enrolment_id))
  );

drop policy if exists absence_requests_update_decider on public.absence_requests;
create policy absence_requests_update_decider on public.absence_requests
  for update
  using (private.can_decide_absence_request(id))
  with check (private.can_decide_absence_request(id));

drop policy if exists absence_request_approvals_select on public.absence_request_approvals;
create policy absence_request_approvals_select on public.absence_request_approvals
  for select
  using (private.can_see_absence_request(request_id));

drop policy if exists absence_request_approvals_write_own on public.absence_request_approvals;
create policy absence_request_approvals_write_own on public.absence_request_approvals
  for all
  using (
    approver_id = auth.uid()
    and private.can_decide_absence_request(request_id)
  )
  with check (
    approver_id = auth.uid()
    and private.can_decide_absence_request(request_id)
  );

drop policy if exists issue_reports_select on public.issue_reports;
create policy issue_reports_select on public.issue_reports
  for select
  using (
    reporter_id = auth.uid()
    or public.is_admin(auth.uid())
  );

drop policy if exists issue_reports_insert_own on public.issue_reports;
create policy issue_reports_insert_own on public.issue_reports
  for insert
  with check (
    reporter_id = auth.uid()
    and status = 'open'
  );

drop policy if exists issue_reports_update_admin on public.issue_reports;
create policy issue_reports_update_admin on public.issue_reports
  for update
  using (public.is_admin(auth.uid()))
  with check (public.is_admin(auth.uid()));
