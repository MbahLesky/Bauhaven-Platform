-- ============================================================================
-- Narrow "entry-only" finance access for the FT-rebuild auth cutover.
--
-- The 2 real FT `staff` users currently have entering-only access in the
-- legacy FT project (can create income/expense/loan/petty-cash/participant-
-- charge records; cannot approve, void, or reverse anything - read access
-- stays broad, per FT_EMERGENCY_SECURITY_HARDENING.md). Every existing
-- main-project role either grants zero finance permissions (`staff`,
-- `organisation_admin`) or bundles create+approve+void+reverse into one
-- `.manage` permission (`finance_manager`) - there is no equivalent of
-- "can enter, cannot approve" today. Granting `finance_manager` to these 2
-- real people would be a real increase in their power (approve/void/reverse
-- rights they don't have in FT) - not authorized, so this migration adds
-- the missing granularity instead.
--
-- See BauhavenDocs/finance-migration/README.md (auth swap section) for the
-- full rationale.
-- ============================================================================

insert into public.permissions (code, domain, name, description, risk_level) values
  ('finance.income.create', 'finance', 'Enter income', 'Create income records (cannot approve/void).', 'medium'),
  ('finance.expenses.create', 'finance', 'Enter expenses', 'Create expense records (cannot approve/void).', 'medium'),
  ('finance.loans.create', 'finance', 'Enter loans', 'Create loans and record repayments.', 'medium'),
  ('finance.charges.create', 'finance', 'Enter participant charges', 'Create participant charges (cannot waive/cancel).', 'medium'),
  ('finance.petty_cash.create', 'finance', 'Enter petty cash', 'Create petty cash entries.', 'low')
on conflict (code) do nothing;

-- staff gets read + create-only across the tables the FT app's "canEnter"
-- gate covered, plus the payment/receipt permissions needed to record a
-- participant payment (recordPayment already issues a receipt in the same
-- flow) - never `.manage`/`.reverse`/`.migration.review`.
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on p.code in (
  'finance.dashboard.read',
  'finance.participants.read',
  'finance.charges.read', 'finance.charges.create',
  'finance.payments.read', 'finance.payments.record',
  'finance.receipts.issue',
  'finance.income.read', 'finance.income.create',
  'finance.expenses.read', 'finance.expenses.create',
  'finance.loans.read', 'finance.loans.create',
  'finance.petty_cash.create'
)
where r.code = 'staff'
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- Split each single "ALL" write policy into INSERT (manage OR create) +
-- UPDATE (manage only) so create-only permissions can't approve/void/edit.
-- ---------------------------------------------------------------------------

drop policy if exists finance_income_write on public.finance_income;
create policy finance_income_insert on public.finance_income
  for insert with check (private.has_permission('finance.income.manage') or private.has_permission('finance.income.create'));
create policy finance_income_update on public.finance_income
  for update using (private.has_permission('finance.income.manage')) with check (private.has_permission('finance.income.manage'));

drop policy if exists finance_expenses_write on public.finance_expenses;
create policy finance_expenses_insert on public.finance_expenses
  for insert with check (private.has_permission('finance.expenses.manage') or private.has_permission('finance.expenses.create'));
create policy finance_expenses_update on public.finance_expenses
  for update using (private.has_permission('finance.expenses.manage')) with check (private.has_permission('finance.expenses.manage'));

drop policy if exists finance_loans_write on public.finance_loans;
create policy finance_loans_insert on public.finance_loans
  for insert with check (private.has_permission('finance.loans.manage') or private.has_permission('finance.loans.create'));
create policy finance_loans_update on public.finance_loans
  for update using (private.has_permission('finance.loans.manage')) with check (private.has_permission('finance.loans.manage'));

drop policy if exists finance_participant_charges_write on public.finance_participant_charges;
create policy finance_participant_charges_insert on public.finance_participant_charges
  for insert with check (private.has_permission('finance.charges.manage') or private.has_permission('finance.charges.create'));
create policy finance_participant_charges_update on public.finance_participant_charges
  for update using (private.has_permission('finance.charges.manage')) with check (private.has_permission('finance.charges.manage'));

drop policy if exists finance_petty_cash_entries_write on public.finance_petty_cash_entries;
create policy finance_petty_cash_entries_insert on public.finance_petty_cash_entries
  for insert with check (private.has_permission('finance.expenses.manage') or private.has_permission('finance.petty_cash.create'));
create policy finance_petty_cash_entries_update on public.finance_petty_cash_entries
  for update using (private.has_permission('finance.expenses.manage')) with check (private.has_permission('finance.expenses.manage'));

drop policy if exists finance_loan_repayments_write on public.finance_loan_repayments;
create policy finance_loan_repayments_insert on public.finance_loan_repayments
  for insert with check (private.has_permission('finance.loans.manage') or private.has_permission('finance.loans.create'));
create policy finance_loan_repayments_update on public.finance_loan_repayments
  for update using (private.has_permission('finance.loans.manage')) with check (private.has_permission('finance.loans.manage'));

-- finance_legacy_participants (migration 0023) also needs the same split,
-- since the founder-authorized "record holiday-class/bootcamp/course
-- participants with their info, no profile" flow is exactly a "canEnter"
-- action, and today it's gated behind finance.charges.manage only.
drop policy if exists finance_legacy_participants_write on public.finance_legacy_participants;
create policy finance_legacy_participants_insert on public.finance_legacy_participants
  for insert with check (private.has_permission('finance.charges.manage') or private.has_permission('finance.charges.create'));
create policy finance_legacy_participants_update on public.finance_legacy_participants
  for update using (private.has_permission('finance.charges.manage')) with check (private.has_permission('finance.charges.manage'));
