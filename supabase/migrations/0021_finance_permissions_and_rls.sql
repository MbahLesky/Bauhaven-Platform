-- ============================================================================
-- Companion to 0020. Adds the finance_manager role, the 18 finance.*
-- permissions (master migration prompt ┬º9.5), role_permissions mappings,
-- and real RLS policies for every finance_* table 0020 created
-- RLS-enabled-but-policy-less.
-- See BauhavenDocs/finance-migration/FINANCE_SCHEMA_MIGRATION_PLAN.md for
-- the reasoning behind the specific roleÔåÆpermission mapping below.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Sequences + reference-number generation (decided design, not a placeholder)
-- ---------------------------------------------------------------------------
create sequence if not exists public.finance_payment_reference_seq;
create sequence if not exists public.finance_receipt_number_seq;

create or replace function public.finance_generate_payment_reference()
returns text
language sql
as $$
  select 'PAY-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.finance_payment_reference_seq')::text, 6, '0');
$$;

create or replace function public.finance_generate_receipt_number()
returns text
language sql
as $$
  select 'RCP-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.finance_receipt_number_seq')::text, 6, '0');
$$;

alter table public.finance_payments alter column internal_reference set default public.finance_generate_payment_reference();
alter table public.finance_receipts alter column receipt_number set default public.finance_generate_receipt_number();

-- ---------------------------------------------------------------------------
-- New role: finance_manager
-- ---------------------------------------------------------------------------
insert into public.roles (code, name, description, is_system, is_active)
values (
  'finance_manager',
  'Finance Manager',
  'Manages participant charges, payments, receipts, and the organisation''s income/expense/loan/budget records. Mirrors the role name already familiar to staff from the legacy Finance Tracker app.',
  true,
  true
)
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- New permissions (18 keys, master prompt ┬º9.5)
-- ---------------------------------------------------------------------------
insert into public.permissions (code, domain, name, description, risk_level) values
  ('finance.dashboard.read', 'finance', 'View finance dashboard', 'View the finance overview dashboard.', 'low'),
  ('finance.participants.read', 'finance', 'View participant fee status', 'View participant charges/balances.', 'low'),
  ('finance.charges.read', 'finance', 'Read charges', 'View participant charges.', 'low'),
  ('finance.charges.manage', 'finance', 'Manage charges', 'Create/edit/waive/cancel participant charges.', 'high'),
  ('finance.payments.read', 'finance', 'Read payments', 'View payment records.', 'low'),
  ('finance.payments.record', 'finance', 'Record payments', 'Record a new payment against a charge.', 'high'),
  ('finance.payments.reverse', 'finance', 'Reverse payments', 'Reverse or refund a confirmed payment.', 'critical'),
  ('finance.receipts.issue', 'finance', 'Issue receipts', 'Issue a receipt for a confirmed payment.', 'medium'),
  ('finance.income.read', 'finance', 'Read income', 'View income records.', 'low'),
  ('finance.income.manage', 'finance', 'Manage income', 'Create/edit/approve/void income records.', 'high'),
  ('finance.expenses.read', 'finance', 'Read expenses', 'View expense records.', 'low'),
  ('finance.expenses.manage', 'finance', 'Manage expenses', 'Create/edit/approve/void expense records.', 'high'),
  ('finance.loans.read', 'finance', 'Read loans', 'View loan records.', 'low'),
  ('finance.loans.manage', 'finance', 'Manage loans', 'Create/edit loans and repayments.', 'high'),
  ('finance.budgets.read', 'finance', 'Read budgets', 'View monthly budget targets.', 'low'),
  ('finance.budgets.manage', 'finance', 'Manage budgets', 'Create/edit monthly budget targets.', 'medium'),
  ('finance.reports.read', 'finance', 'Read finance reports', 'View/export finance reports.', 'low'),
  ('finance.migration.review', 'finance', 'Review migration exceptions', 'Review and resolve FT-migration exceptions and access raw legacy import data.', 'critical')
on conflict (code) do nothing;

-- ---------------------------------------------------------------------------
-- Role ÔåÆ permission mapping (see the plan doc for the reasoning)
-- ---------------------------------------------------------------------------
insert into public.role_permissions (role_id, permission_id)
select r.id, p.id
from public.roles r
join public.permissions p on (
  (r.code = 'super_admin' and p.domain = 'finance')
  or (r.code = 'finance_manager' and p.domain = 'finance' and p.code <> 'finance.migration.review')
  or (r.code = 'auditor' and p.code in ('finance.dashboard.read', 'finance.reports.read'))
)
on conflict do nothing;

-- ---------------------------------------------------------------------------
-- RLS policies. Every finance_* table checks organisation-wide permission
-- only (no offering/cohort scoping) - unlike Admissions/Programmes, finance
-- data doesn't have a clean single offering/cohort owner per row in every
-- table (e.g. `finance_income` may have no charge_id at all), so scoping is
-- deliberately left at the organisation level for this first pass. This can
-- be tightened to scope-aware policies later if a real need for
-- offering-scoped finance staff emerges - not assumed here.
-- ---------------------------------------------------------------------------

drop policy if exists finance_fee_plans_read on public.finance_fee_plans;
create policy finance_fee_plans_read on public.finance_fee_plans
  for select using (private.has_permission('finance.dashboard.read') or private.has_permission('finance.charges.read'));
drop policy if exists finance_fee_plans_write on public.finance_fee_plans;
create policy finance_fee_plans_write on public.finance_fee_plans
  for all using (private.has_permission('finance.charges.manage')) with check (private.has_permission('finance.charges.manage'));

drop policy if exists finance_participant_charges_read on public.finance_participant_charges;
create policy finance_participant_charges_read on public.finance_participant_charges
  for select using (private.has_permission('finance.charges.read') or private.has_permission('finance.participants.read'));
drop policy if exists finance_participant_charges_write on public.finance_participant_charges;
create policy finance_participant_charges_write on public.finance_participant_charges
  for all using (private.has_permission('finance.charges.manage')) with check (private.has_permission('finance.charges.manage'));

drop policy if exists finance_payments_read on public.finance_payments;
create policy finance_payments_read on public.finance_payments
  for select using (private.has_permission('finance.payments.read') or payer_profile_id = auth.uid());
drop policy if exists finance_payments_insert on public.finance_payments;
create policy finance_payments_insert on public.finance_payments
  for insert with check (private.has_permission('finance.payments.record'));
drop policy if exists finance_payments_update on public.finance_payments;
create policy finance_payments_update on public.finance_payments
  for update
  using (
    private.has_permission('finance.payments.record')
    or (status = 'confirmed' and private.has_permission('finance.payments.reverse'))
  )
  with check (
    private.has_permission('finance.payments.record')
    or private.has_permission('finance.payments.reverse')
  );

drop policy if exists finance_payment_allocations_read on public.finance_payment_allocations;
create policy finance_payment_allocations_read on public.finance_payment_allocations
  for select using (private.has_permission('finance.payments.read') or private.has_permission('finance.charges.read'));
drop policy if exists finance_payment_allocations_write on public.finance_payment_allocations;
create policy finance_payment_allocations_write on public.finance_payment_allocations
  for all using (private.has_permission('finance.payments.record')) with check (private.has_permission('finance.payments.record'));

drop policy if exists finance_receipts_read on public.finance_receipts;
create policy finance_receipts_read on public.finance_receipts
  for select using (private.has_permission('finance.payments.read'));
drop policy if exists finance_receipts_write on public.finance_receipts;
create policy finance_receipts_write on public.finance_receipts
  for all using (private.has_permission('finance.receipts.issue')) with check (private.has_permission('finance.receipts.issue'));

drop policy if exists finance_payment_accounts_read on public.finance_payment_accounts;
create policy finance_payment_accounts_read on public.finance_payment_accounts
  for select using (private.has_permission('finance.dashboard.read'));
drop policy if exists finance_payment_accounts_write on public.finance_payment_accounts;
create policy finance_payment_accounts_write on public.finance_payment_accounts
  for all using (private.has_permission('finance.budgets.manage')) with check (private.has_permission('finance.budgets.manage'));

drop policy if exists finance_expense_categories_read on public.finance_expense_categories;
create policy finance_expense_categories_read on public.finance_expense_categories
  for select using (private.has_permission('finance.expenses.read') or private.has_permission('finance.dashboard.read'));
drop policy if exists finance_expense_categories_write on public.finance_expense_categories;
create policy finance_expense_categories_write on public.finance_expense_categories
  for all using (private.has_permission('finance.expenses.manage')) with check (private.has_permission('finance.expenses.manage'));

drop policy if exists finance_income_read on public.finance_income;
create policy finance_income_read on public.finance_income
  for select using (private.has_permission('finance.income.read'));
drop policy if exists finance_income_write on public.finance_income;
create policy finance_income_write on public.finance_income
  for all using (private.has_permission('finance.income.manage')) with check (private.has_permission('finance.income.manage'));

drop policy if exists finance_expenses_read on public.finance_expenses;
create policy finance_expenses_read on public.finance_expenses
  for select using (private.has_permission('finance.expenses.read'));
drop policy if exists finance_expenses_write on public.finance_expenses;
create policy finance_expenses_write on public.finance_expenses
  for all using (private.has_permission('finance.expenses.manage')) with check (private.has_permission('finance.expenses.manage'));

drop policy if exists finance_loans_read on public.finance_loans;
create policy finance_loans_read on public.finance_loans
  for select using (private.has_permission('finance.loans.read'));
drop policy if exists finance_loans_write on public.finance_loans;
create policy finance_loans_write on public.finance_loans
  for all using (private.has_permission('finance.loans.manage')) with check (private.has_permission('finance.loans.manage'));

drop policy if exists finance_loan_repayments_read on public.finance_loan_repayments;
create policy finance_loan_repayments_read on public.finance_loan_repayments
  for select using (private.has_permission('finance.loans.read'));
drop policy if exists finance_loan_repayments_write on public.finance_loan_repayments;
create policy finance_loan_repayments_write on public.finance_loan_repayments
  for all using (private.has_permission('finance.loans.manage')) with check (private.has_permission('finance.loans.manage'));

drop policy if exists finance_budgets_read on public.finance_budgets;
create policy finance_budgets_read on public.finance_budgets
  for select using (private.has_permission('finance.budgets.read'));
drop policy if exists finance_budgets_write on public.finance_budgets;
create policy finance_budgets_write on public.finance_budgets
  for all using (private.has_permission('finance.budgets.manage')) with check (private.has_permission('finance.budgets.manage'));

drop policy if exists finance_invoices_read on public.finance_invoices;
create policy finance_invoices_read on public.finance_invoices
  for select using (private.has_permission('finance.charges.read'));
drop policy if exists finance_invoices_write on public.finance_invoices;
create policy finance_invoices_write on public.finance_invoices
  for all using (private.has_permission('finance.charges.manage')) with check (private.has_permission('finance.charges.manage'));

drop policy if exists finance_invoice_items_read on public.finance_invoice_items;
create policy finance_invoice_items_read on public.finance_invoice_items
  for select using (private.has_permission('finance.charges.read'));
drop policy if exists finance_invoice_items_write on public.finance_invoice_items;
create policy finance_invoice_items_write on public.finance_invoice_items
  for all using (private.has_permission('finance.charges.manage')) with check (private.has_permission('finance.charges.manage'));

drop policy if exists finance_petty_cash_entries_read on public.finance_petty_cash_entries;
create policy finance_petty_cash_entries_read on public.finance_petty_cash_entries
  for select using (private.has_permission('finance.expenses.read'));
drop policy if exists finance_petty_cash_entries_write on public.finance_petty_cash_entries;
create policy finance_petty_cash_entries_write on public.finance_petty_cash_entries
  for all using (private.has_permission('finance.expenses.manage')) with check (private.has_permission('finance.expenses.manage'));

drop policy if exists finance_transaction_events_read on public.finance_transaction_events;
create policy finance_transaction_events_read on public.finance_transaction_events
  for select using (private.has_permission('finance.reports.read') or private.has_permission('audit.read'));
-- No write policy: finance_transaction_events is populated only by
-- SECURITY DEFINER trigger functions (added alongside the tables that need
-- them, in a follow-up migration once the application layer's exact
-- mutation points are implemented) - never directly by a client.

-- Migration-only tables: super_admin (via finance.migration.review) only.
drop policy if exists ft_import_participants_review on public.ft_import_participants;
create policy ft_import_participants_review on public.ft_import_participants
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_users_review on public.ft_import_users;
create policy ft_import_users_review on public.ft_import_users
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_income_review on public.ft_import_income;
create policy ft_import_income_review on public.ft_import_income
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_expenses_review on public.ft_import_expenses;
create policy ft_import_expenses_review on public.ft_import_expenses
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_loans_review on public.ft_import_loans;
create policy ft_import_loans_review on public.ft_import_loans
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_payment_accounts_review on public.ft_import_payment_accounts;
create policy ft_import_payment_accounts_review on public.ft_import_payment_accounts
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_budgets_review on public.ft_import_budgets;
create policy ft_import_budgets_review on public.ft_import_budgets
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_invoices_review on public.ft_import_invoices;
create policy ft_import_invoices_review on public.ft_import_invoices
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_petty_cash_review on public.ft_import_petty_cash;
create policy ft_import_petty_cash_review on public.ft_import_petty_cash
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_attendance_review on public.ft_import_attendance;
create policy ft_import_attendance_review on public.ft_import_attendance
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists ft_import_audit_log_review on public.ft_import_audit_log;
create policy ft_import_audit_log_review on public.ft_import_audit_log
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists integration_ft_id_map_review on public.integration_ft_id_map;
create policy integration_ft_id_map_review on public.integration_ft_id_map
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists finance_migration_batches_review on public.finance_migration_batches;
create policy finance_migration_batches_review on public.finance_migration_batches
  for select using (private.has_permission('finance.migration.review'));
drop policy if exists finance_migration_exceptions_review on public.finance_migration_exceptions;
create policy finance_migration_exceptions_review on public.finance_migration_exceptions
  for all using (private.has_permission('finance.migration.review')) with check (private.has_permission('finance.migration.review'));

-- No write policies on the ft_import_*/integration_ft_id_map tables at all -
-- those are populated exclusively by the service-role migration scripts
-- (Phase 2), never by an authenticated client, matching the same pattern
-- already used for audit_logs (written only by SECURITY DEFINER functions
-- or service-role Edge Functions).
