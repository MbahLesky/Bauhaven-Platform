-- ============================================================================
-- 0053: Link Finance Records to Platform Users & Track Tuition Coverage
--
-- 1. Links finance_legacy_participants, finance_income, and finance_payments
--    directly to registered user profiles (public.profiles(id)).
-- 2. Adds period_start and period_end to finance_participant_charges and
--    finance_income to track subscription/tuition coverage windows.
-- 3. Grants Row-Level Security (RLS) so learners and interns can view their
--    own charges, payment records, and balances.
-- 4. Updates public.finance_participant_balances view to include profile_id,
--    period_start, and period_end for dashboard coverage calculations.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Add profile linkage and coverage dates to finance tables
-- ---------------------------------------------------------------------------
alter table public.finance_legacy_participants
  add column if not exists profile_id uuid references public.profiles (id) on delete set null;

create index if not exists finance_legacy_participants_profile_id_idx
  on public.finance_legacy_participants (profile_id);

alter table public.finance_participant_charges
  add column if not exists period_start date,
  add column if not exists period_end date;

alter table public.finance_payments
  add column if not exists payer_profile_id uuid references public.profiles (id) on delete set null;

create index if not exists finance_payments_payer_profile_id_idx
  on public.finance_payments (payer_profile_id);

alter table public.finance_income
  add column if not exists payer_profile_id uuid references public.profiles (id) on delete set null,
  add column if not exists enrolment_id uuid references public.enrolments (id) on delete set null,
  add column if not exists legacy_participant_id uuid references public.finance_legacy_participants (id) on delete set null,
  add column if not exists period_start date,
  add column if not exists period_end date;

create index if not exists finance_income_payer_profile_id_idx
  on public.finance_income (payer_profile_id);

create index if not exists finance_income_enrolment_id_idx
  on public.finance_income (enrolment_id);

create index if not exists finance_income_legacy_participant_id_idx
  on public.finance_income (legacy_participant_id);

-- ---------------------------------------------------------------------------
-- 2. Update Row-Level Security (RLS) for Participant / Learner visibility
-- ---------------------------------------------------------------------------

-- Charges: Admins/Finance can manage all; learners can read their own
drop policy if exists finance_participant_charges_read on public.finance_participant_charges;
create policy finance_participant_charges_read on public.finance_participant_charges
  for select using (
    private.has_permission('finance.charges.read')
    or private.has_permission('finance.participants.read')
    or (
      enrolment_id is not null and exists (
        select 1 from public.enrolments e
        where e.id = finance_participant_charges.enrolment_id
          and e.profile_id = auth.uid()
      )
    )
    or (
      legacy_participant_id is not null and exists (
        select 1 from public.finance_legacy_participants lp
        where lp.id = finance_participant_charges.legacy_participant_id
          and lp.profile_id = auth.uid()
      )
    )
  );

-- Payments: Admins/Finance can read all; payer can read their own
drop policy if exists finance_payments_read on public.finance_payments;
create policy finance_payments_read on public.finance_payments
  for select using (
    private.has_permission('finance.payments.read')
    or payer_profile_id = auth.uid()
    or exists (
      select 1 from public.finance_payment_allocations a
      join public.finance_participant_charges c on c.id = a.charge_id
      left join public.enrolments e on e.id = c.enrolment_id
      left join public.finance_legacy_participants lp on lp.id = c.legacy_participant_id
      where a.payment_id = finance_payments.id
        and (e.profile_id = auth.uid() or lp.profile_id = auth.uid())
    )
  );

-- Payment allocations: Read if you can read the payment or charge
drop policy if exists finance_payment_allocations_read on public.finance_payment_allocations;
create policy finance_payment_allocations_read on public.finance_payment_allocations
  for select using (
    private.has_permission('finance.payments.read')
    or exists (
      select 1 from public.finance_payments p
      where p.id = finance_payment_allocations.payment_id
        and p.payer_profile_id = auth.uid()
    )
    or exists (
      select 1 from public.finance_participant_charges c
      left join public.enrolments e on e.id = c.enrolment_id
      left join public.finance_legacy_participants lp on lp.id = c.legacy_participant_id
      where c.id = finance_payment_allocations.charge_id
        and (e.profile_id = auth.uid() or lp.profile_id = auth.uid())
    )
  );

-- Legacy participants: Read if you hold finance permission or are the linked user
drop policy if exists finance_legacy_participants_read on public.finance_legacy_participants;
create policy finance_legacy_participants_read on public.finance_legacy_participants
  for select using (
    private.has_permission('finance.participants.read')
    or private.has_permission('finance.charges.read')
    or profile_id = auth.uid()
  );

-- Income: Read if you hold finance permission or are the payer
drop policy if exists finance_income_read on public.finance_income;
create policy finance_income_read on public.finance_income
  for select using (
    private.has_permission('finance.income.read')
    or payer_profile_id = auth.uid()
  );

-- ---------------------------------------------------------------------------
-- 3. Enhanced finance_participant_balances View
-- ---------------------------------------------------------------------------
drop view if exists public.finance_participant_balances;
create view public.finance_participant_balances as
select
  c.id as charge_id,
  c.enrolment_id,
  c.legacy_participant_id,
  coalesce(e.profile_id, lp.profile_id) as profile_id,
  coalesce(lp.full_name, pr.full_name, 'Participant') as participant_name,
  coalesce(lp.email, pr.email) as participant_email,
  c.description as charge_description,
  c.currency,
  c.original_amount,
  c.discount_amount,
  c.waiver_amount,
  c.amount_due,
  coalesce(sum(a.allocated_amount) filter (where p.status = 'confirmed'), 0) as amount_paid,
  c.amount_due - coalesce(sum(a.allocated_amount) filter (where p.status = 'confirmed'), 0) as outstanding_balance,
  c.due_date,
  coalesce(c.period_start, lp.start_date, c.created_at::date) as period_start,
  coalesce(
    c.period_end,
    lp.expiry_date,
    c.due_date,
    (coalesce(c.period_start, lp.start_date, c.created_at::date) + interval '30 days')::date
  ) as period_end,
  case
    when c.status = 'waived' then 'Waived'
    when c.status = 'cancelled' then 'Cancelled'
    when coalesce(sum(a.allocated_amount) filter (where p.status = 'confirmed'), 0) >= c.amount_due then 'Paid'
    when coalesce(sum(a.allocated_amount) filter (where p.status = 'confirmed'), 0) > 0 then 'Partially Paid'
    when c.due_date is not null and c.due_date < current_date then 'Overdue'
    else 'Outstanding'
  end as display_status
from public.finance_participant_charges c
left join public.finance_payment_allocations a on a.charge_id = c.id
left join public.finance_payments p on p.id = a.payment_id
left join public.enrolments e on e.id = c.enrolment_id
left join public.finance_legacy_participants lp on lp.id = c.legacy_participant_id
left join public.profiles pr on pr.id = coalesce(e.profile_id, lp.profile_id)
group by
  c.id,
  c.enrolment_id,
  c.legacy_participant_id,
  e.profile_id,
  lp.profile_id,
  lp.full_name,
  pr.full_name,
  lp.email,
  pr.email,
  c.description,
  c.currency,
  c.original_amount,
  c.discount_amount,
  c.waiver_amount,
  c.amount_due,
  c.status,
  c.due_date,
  c.period_start,
  c.period_end,
  lp.start_date,
  lp.expiry_date,
  c.created_at;

grant select on public.finance_participant_balances to authenticated, anon;
