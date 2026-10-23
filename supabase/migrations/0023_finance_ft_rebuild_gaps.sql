-- ============================================================================
-- Second batch of gaps found while implementing the bauhaven_ft rebuild's
-- data layer against the canonical finance_* schema. See
-- BauhavenDocs/finance-migration/FT_REBUILD_DATA_LAYER_MAPPING.md ┬º5b for
-- the full rationale behind each change below.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Small additive columns - the old FT app captures these; dropping them
--    silently would be a feature regression, not a simplification.
-- ---------------------------------------------------------------------------
alter table public.finance_loan_repayments
  add column if not exists payment_method text;

alter table public.finance_invoices
  add column if not exists paid_date timestamptz,
  add column if not exists void_reason text,
  add column if not exists voided_by uuid references public.profiles (id);

-- ---------------------------------------------------------------------------
-- 2. finance_legacy_participants - a real, local home for participants who
--    (per the founder's type-based rule) don't get a profile/enrolment:
--    holiday_class/bootcamp/course by default, plus internship participants
--    recorded before Admin's enrolment picker exists (tracked separately in
--    ADMIN_FINANCE_MODULE.md's own known gaps - not silently dropped here).
--    `finance_participant_charges.legacy_participant_id` stays a bare,
--    unconstrained uuid (unchanged) so it can still tolerate dangling
--    references into the old FT project's database during Phase 2 migration;
--    this table is simply a real target for it going forward.
-- ---------------------------------------------------------------------------
create table if not exists public.finance_legacy_participants (
  id uuid primary key default gen_random_uuid(),
  type text not null check (type in ('internship', 'holiday_class', 'bootcamp', 'course')),
  full_name text not null,
  email text,
  phone text,
  school text,
  department text,
  program text,
  id_card_number text,
  guardian_name text,
  guardian_phone text,
  referral_source text,
  referral_person_name text,
  referral_fee_due numeric(14, 2) not null default 0,
  referral_fee_paid boolean not null default false,
  referral_fee_payment_date date,
  start_date date,
  duration text,
  expiry_date date,
  status text not null default 'enrolled' check (
    status in ('enrolled', 'in_progress', 'completed', 'certificate_issued', 'dropped')
  ),
  waitlist boolean not null default false,
  notes text,
  created_by uuid references public.profiles (id),
  legacy_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists finance_legacy_participants_set_updated_at on public.finance_legacy_participants;
create trigger finance_legacy_participants_set_updated_at
  before update on public.finance_legacy_participants
  for each row execute function public.set_updated_at();

alter table public.finance_legacy_participants enable row level security;

drop policy if exists finance_legacy_participants_read on public.finance_legacy_participants;
create policy finance_legacy_participants_read on public.finance_legacy_participants
  for select using (private.has_permission('finance.participants.read') or private.has_permission('finance.charges.read'));

drop policy if exists finance_legacy_participants_write on public.finance_legacy_participants;
create policy finance_legacy_participants_write on public.finance_legacy_participants
  for all using (private.has_permission('finance.charges.manage')) with check (private.has_permission('finance.charges.manage'));

-- ---------------------------------------------------------------------------
-- 3. finance_log_event - a SECURITY DEFINER RPC replacing a direct client
--    insert into finance_transaction_events (which has no write policy by
--    design - see migration 0021's own comment). Forces actor_id to the
--    caller's own auth.uid() server-side, so a business-level event name
--    ('approved_income', 'voided_transaction', ...) can be logged precisely
--    at the point the app performs it, without opening a policy that would
--    let a client insert an event under someone else's identity.
-- ---------------------------------------------------------------------------
create or replace function public.finance_log_event(
  p_event_type text,
  p_entity_type text,
  p_entity_id uuid,
  p_before jsonb default null,
  p_after jsonb default null,
  p_source_system text default 'bauhaven_ft'
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.finance_transaction_events (
    event_type, entity_type, entity_id, actor_id, before_data, after_data, source_system
  ) values (
    p_event_type, p_entity_type, p_entity_id, auth.uid(), p_before, p_after, p_source_system
  );
end;
$$;

grant execute on function public.finance_log_event(text, text, uuid, jsonb, jsonb, text) to authenticated;
