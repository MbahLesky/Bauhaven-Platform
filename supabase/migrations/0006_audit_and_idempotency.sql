-- Bauhaven Admin - audit log and idempotency
--
-- audit_logs.id is `bigint generated always as identity`, matching the
-- literal type in the platform's Database Schema/Data Dictionary technical
-- document (this repo's first draft used uuid - corrected here since no
-- migration has been applied live yet).

create table if not exists public.audit_logs (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id uuid references public.profiles (id),
  action text not null,
  entity_type text not null,
  entity_id text not null,
  before_data jsonb,
  after_data jsonb,
  outcome text not null default 'success' check (outcome in ('success', 'failure')),
  metadata jsonb not null default '{}'::jsonb,
  request_id uuid
);

create index if not exists audit_logs_entity_idx on public.audit_logs (entity_type, entity_id);
create index if not exists audit_logs_occurred_at_idx on public.audit_logs (occurred_at desc);

create or replace function public.log_audit_event(
  p_actor_id uuid,
  p_action text,
  p_entity_type text,
  p_entity_id text,
  p_before jsonb,
  p_after jsonb,
  p_outcome text default 'success',
  p_metadata jsonb default '{}'::jsonb,
  p_request_id uuid default null
)
returns bigint
language plpgsql
security definer
set search_path = public
as $$
declare
  new_id bigint;
begin
  insert into public.audit_logs (actor_id, action, entity_type, entity_id, before_data, after_data, outcome, metadata, request_id)
  values (p_actor_id, p_action, p_entity_type, p_entity_id, p_before, p_after, p_outcome, p_metadata, p_request_id)
  returning id into new_id;
  return new_id;
end;
$$;

-- Every application/enrolment status change is already captured by the
-- dedicated *_status_history tables (0004/0005), which are the applicant/
-- learner-facing timeline. audit_logs additionally records the specific
-- privileged actions below (approval, invitation) for security review.

-- ---------------------------------------------------------------------------
-- idempotency_keys (04_BAUHAVEN_DATABASE_SCHEMA.md section 13.2). Available
-- for any future privileged Edge Function that needs a generic replay guard.
-- approve-application does not use this table directly: Technical Foundation
-- D's own operation contract for it says "Application id is natural
-- idempotency key; retries reuse enrolment and invitation state," which is
-- exactly the unique-index-on-application_id guard already in
-- 0005_invitations_and_enrolments.sql. This table is seeded here so it's
-- ready for reject-application, invite-resend, publish-content, etc.
-- ---------------------------------------------------------------------------
create table if not exists public.idempotency_keys (
  key text primary key,
  operation text not null,
  actor_id uuid references public.profiles (id),
  request_hash text,
  status text not null default 'processing' check (status in ('processing', 'completed', 'failed')),
  response jsonb,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '24 hours')
);

create index if not exists idempotency_keys_expires_at_idx on public.idempotency_keys (expires_at);
