-- Bauhaven Admin - invitations and enrolments
-- Shapes follow 04_BAUHAVEN_DATABASE_SCHEMA.md sections 7.1-7.3.

create table if not exists public.invitations (
  id uuid primary key default gen_random_uuid(),
  application_id uuid references public.applications (id) on delete set null,
  enrolment_id uuid,
  email citext not null,
  token_hash text,
  status public.invitation_status not null default 'queued',
  expires_at timestamptz,
  sent_at timestamptz,
  accepted_at timestamptz,
  revoked_at timestamptz,
  provider_message_id text,
  attempt_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists invitations_application_id_idx on public.invitations (application_id);
create index if not exists invitations_email_idx on public.invitations (lower(email::text));

drop trigger if exists invitations_set_updated_at on public.invitations;
create trigger invitations_set_updated_at
  before update on public.invitations
  for each row execute function public.set_updated_at();

create table if not exists public.enrolments (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  application_id uuid references public.applications (id) on delete set null,
  offering_id uuid references public.offerings (id),
  cohort_id uuid references public.cohorts (id),
  assigned_role text not null default 'Intern',
  mentor_id uuid references public.profiles (id),
  status public.enrolment_status not null default 'pending_activation',
  activated_at timestamptz,
  started_at date,
  completed_at timestamptz,
  withdrawn_at timestamptz,
  reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists enrolments_profile_id_idx on public.enrolments (profile_id);

-- Idempotency guard the approve-application Edge Function relies on: at
-- most one enrolment per application (04_BAUHAVEN_DATABASE_SCHEMA.md
-- section 7.2 "Recommended unique rule", specialised to the one-application-
-- one-approval invariant this MVP actually needs).
create unique index if not exists enrolments_application_id_unique
  on public.enrolments (application_id)
  where application_id is not null;

drop trigger if exists enrolments_set_updated_at on public.enrolments;
create trigger enrolments_set_updated_at
  before update on public.enrolments
  for each row execute function public.set_updated_at();

alter table public.application_approvals
  add constraint application_approvals_enrolment_id_fkey
  foreign key (enrolment_id) references public.enrolments (id) on delete set null;

-- ---------------------------------------------------------------------------
-- enrolment_status_history: append-only (section 7.3).
-- ---------------------------------------------------------------------------
create table if not exists public.enrolment_status_history (
  id uuid primary key default gen_random_uuid(),
  enrolment_id uuid not null references public.enrolments (id) on delete cascade,
  from_status public.enrolment_status,
  to_status public.enrolment_status not null,
  actor_id uuid references public.profiles (id),
  reason text,
  created_at timestamptz not null default now()
);

create or replace function public.record_enrolment_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.enrolment_status_history (enrolment_id, from_status, to_status, actor_id, reason)
    values (new.id, null, new.status, auth.uid(), new.reason);
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
    insert into public.enrolment_status_history (enrolment_id, from_status, to_status, actor_id, reason)
    values (new.id, old.status, new.status, auth.uid(), new.reason);
  end if;
  return new;
end;
$$;

drop trigger if exists enrolments_record_status_history on public.enrolments;
create trigger enrolments_record_status_history
  after insert or update on public.enrolments
  for each row execute function public.record_enrolment_status_change();
