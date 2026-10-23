-- ============================================================================
-- Canonical finance schema for the Bauhaven Financial Tracker migration.
-- See BauhavenDocs/finance-migration/FINANCE_SCHEMA_MIGRATION_PLAN.md for the
-- full design rationale (reference-number schemes, permission mapping,
-- participant-profile-linking rule) - all resolved before this was applied.
--
-- Owning repo/system: bauhaven-admin/supabase/migrations/ (see
-- SCHEMA_OWNERSHIP_REGISTER.md - Website's Drizzle layer must never touch
-- anything in this file).
--
-- Namespaced `finance_*` throughout specifically so a repeat of the
-- `public.projects` collision (found live, see the audit report) is
-- structurally harder even if the ownership register is forgotten.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Fee plans
-- ---------------------------------------------------------------------------
create table if not exists public.finance_fee_plans (
  id uuid primary key default gen_random_uuid(),
  offering_id uuid references public.offerings (id),
  cohort_id uuid references public.cohorts (id),
  name text not null,
  description text,
  currency text not null default 'XAF',
  base_amount numeric(14, 2) not null check (base_amount >= 0),
  due_date date,
  allows_installments boolean not null default true,
  status text not null default 'active' check (status in ('draft', 'active', 'archived')),
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_fee_plans_context_required check (offering_id is not null or cohort_id is not null)
);

drop trigger if exists finance_fee_plans_set_updated_at on public.finance_fee_plans;
create trigger finance_fee_plans_set_updated_at
  before update on public.finance_fee_plans
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 2. Participant charges
-- ---------------------------------------------------------------------------
create table if not exists public.finance_participant_charges (
  id uuid primary key default gen_random_uuid(),
  enrolment_id uuid references public.enrolments (id),
  -- Plain uuid, NOT a foreign key: this may reference a row in the *legacy*
  -- FT project's `participants` table, a different physical database that
  -- Postgres cannot enforce a constraint against. Populated only for
  -- migrated records; null for charges created fresh going forward.
  legacy_participant_id uuid,
  fee_plan_id uuid references public.finance_fee_plans (id),
  description text not null default '',
  currency text not null default 'XAF',
  original_amount numeric(14, 2) not null check (original_amount >= 0),
  discount_amount numeric(14, 2) not null default 0 check (discount_amount >= 0),
  waiver_amount numeric(14, 2) not null default 0 check (waiver_amount >= 0),
  amount_due numeric(14, 2) not null check (amount_due >= 0),
  due_date date,
  status text not null default 'draft' check (
    status in ('draft', 'active', 'partially_paid', 'paid', 'overdue', 'waived', 'cancelled')
  ),
  source_system text not null default 'bauhaven_admin' check (source_system in ('bauhaven_admin', 'bauhaven_ft')),
  source_id text,
  created_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_participant_charges_identity_required check (enrolment_id is not null or legacy_participant_id is not null)
);

create index if not exists finance_participant_charges_enrolment_id_idx on public.finance_participant_charges (enrolment_id);
create index if not exists finance_participant_charges_legacy_participant_id_idx on public.finance_participant_charges (legacy_participant_id);
create index if not exists finance_participant_charges_status_idx on public.finance_participant_charges (status);

drop trigger if exists finance_participant_charges_set_updated_at on public.finance_participant_charges;
create trigger finance_participant_charges_set_updated_at
  before update on public.finance_participant_charges
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 3. Payments (append-only in spirit - the app layer must never UPDATE
--    amount/status in place except via the reversal/refund status values;
--    see FINANCE_SCHEMA_MIGRATION_PLAN.md for why this is enforced at the
--    application layer, not by making the table literally immutable, since
--    a `status` transition to 'reversed'/'refunded' is itself a real,
--    necessary update)
-- ---------------------------------------------------------------------------
create table if not exists public.finance_payments (
  id uuid primary key default gen_random_uuid(),
  payer_profile_id uuid references public.profiles (id),
  legacy_participant_id uuid,
  currency text not null default 'XAF',
  amount numeric(14, 2) not null check (amount > 0),
  payment_date timestamptz not null default now(),
  payment_method text not null check (payment_method in ('cash', 'mtn_momo', 'orange_money', 'bank_transfer', 'other')),
  external_reference text,
  internal_reference text not null unique,
  status text not null default 'pending' check (
    status in ('pending', 'confirmed', 'failed', 'reversed', 'refunded', 'cancelled')
  ),
  notes text,
  source_system text not null default 'bauhaven_admin' check (source_system in ('bauhaven_admin', 'bauhaven_ft')),
  source_id text,
  recorded_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint finance_payments_identity_required check (payer_profile_id is not null or legacy_participant_id is not null)
);

create index if not exists finance_payments_payer_profile_id_idx on public.finance_payments (payer_profile_id);
create index if not exists finance_payments_status_idx on public.finance_payments (status);

drop trigger if exists finance_payments_set_updated_at on public.finance_payments;
create trigger finance_payments_set_updated_at
  before update on public.finance_payments
  for each row execute function public.set_updated_at();

-- ---------------------------------------------------------------------------
-- 4. Payment allocations (a payment can cover one or more charges; a charge
--    can be paid off by one or more payments - this is the join table that
--    the legacy FT schema never had)
-- ---------------------------------------------------------------------------
create table if not exists public.finance_payment_allocations (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.finance_payments (id) on delete cascade,
  charge_id uuid not null references public.finance_participant_charges (id) on delete cascade,
  allocated_amount numeric(14, 2) not null check (allocated_amount > 0),
  created_at timestamptz not null default now(),
  unique (payment_id, charge_id)
);

create index if not exists finance_payment_allocations_charge_id_idx on public.finance_payment_allocations (charge_id);

-- ---------------------------------------------------------------------------
-- 5. Receipts
-- ---------------------------------------------------------------------------
create table if not exists public.finance_receipts (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null unique references public.finance_payments (id) on delete cascade,
  receipt_number text not null unique,
  issued_at timestamptz not null default now(),
  issued_by uuid references public.profiles (id),
  document_path text,
  verification_code text not null unique default encode(gen_random_bytes(9), 'hex'),
  status text not null default 'issued' check (status in ('issued', 'void')),
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 6. Income / expenses / supporting finance tables (canonical equivalents of
--    every non-participant FT table, per master prompt ┬º5.6, with real FKs
--    replacing FT's unenforced text links)
-- ---------------------------------------------------------------------------
create table if not exists public.finance_payment_accounts (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique,
  currency text not null default 'XAF',
  current_balance numeric(14, 2) not null default 0,
  is_active boolean not null default true,
  legacy_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists finance_payment_accounts_set_updated_at on public.finance_payment_accounts;
create trigger finance_payment_accounts_set_updated_at
  before update on public.finance_payment_accounts
  for each row execute function public.set_updated_at();

create table if not exists public.finance_expense_categories (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  is_active boolean not null default true
);

insert into public.finance_expense_categories (code, name) values
  ('office_supplies', 'Office Supplies'),
  ('electricity', 'Electricity'),
  ('internet', 'Internet'),
  ('training_materials', 'Training Materials'),
  ('referral_bonus', 'Referral Bonus'),
  ('marketing', 'Marketing'),
  ('borrowed_money', 'Loan Given Out'),
  ('salary', 'Salary'),
  ('asset_purchase', 'Asset Purchase'),
  ('others', 'Others')
on conflict (code) do nothing;

create table if not exists public.finance_income (
  id uuid primary key default gen_random_uuid(),
  source text not null,
  charge_id uuid references public.finance_participant_charges (id),
  payment_account_id uuid references public.finance_payment_accounts (id),
  description text not null default '',
  currency text not null default 'XAF',
  amount numeric(14, 2) not null check (amount >= 0),
  approval_status text not null default 'pending' check (
    approval_status in ('pending', 'confirmed', 'voided', 'self_approved_flagged')
  ),
  void_reason text,
  entered_by uuid references public.profiles (id),
  approved_by uuid references public.profiles (id),
  voided_by uuid references public.profiles (id),
  legacy_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists finance_income_set_updated_at on public.finance_income;
create trigger finance_income_set_updated_at
  before update on public.finance_income
  for each row execute function public.set_updated_at();

create table if not exists public.finance_expenses (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.finance_expense_categories (id),
  custom_category text,
  description text not null default '',
  currency text not null default 'XAF',
  amount numeric(14, 2) not null check (amount >= 0),
  payment_method text,
  payment_account_id uuid references public.finance_payment_accounts (id),
  person_in_charge text,
  approval_status text not null default 'pending' check (
    approval_status in ('pending', 'confirmed', 'voided', 'self_approved_flagged')
  ),
  void_reason text,
  entered_by uuid references public.profiles (id),
  approved_by uuid references public.profiles (id),
  voided_by uuid references public.profiles (id),
  legacy_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists finance_expenses_set_updated_at on public.finance_expenses;
create trigger finance_expenses_set_updated_at
  before update on public.finance_expenses
  for each row execute function public.set_updated_at();

create table if not exists public.finance_loans (
  id uuid primary key default gen_random_uuid(),
  person_name text not null,
  person_phone text,
  amount_borrowed numeric(14, 2) not null check (amount_borrowed >= 0),
  date_borrowed timestamptz not null default now(),
  deadline timestamptz,
  status text not null default 'active' check (status in ('active', 'repaid', 'written_off')),
  notes text,
  created_by uuid references public.profiles (id),
  legacy_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists finance_loans_set_updated_at on public.finance_loans;
create trigger finance_loans_set_updated_at
  before update on public.finance_loans
  for each row execute function public.set_updated_at();

create table if not exists public.finance_loan_repayments (
  id uuid primary key default gen_random_uuid(),
  loan_id uuid not null references public.finance_loans (id) on delete cascade,
  amount numeric(14, 2) not null check (amount > 0),
  repaid_at timestamptz not null default now(),
  recorded_by uuid references public.profiles (id),
  created_at timestamptz not null default now()
);

create index if not exists finance_loan_repayments_loan_id_idx on public.finance_loan_repayments (loan_id);

create table if not exists public.finance_budgets (
  id uuid primary key default gen_random_uuid(),
  month integer not null check (month between 1 and 12),
  year integer not null,
  income_targets jsonb not null default '{}'::jsonb,
  expense_targets jsonb not null default '{}'::jsonb,
  created_by uuid references public.profiles (id),
  legacy_id uuid,
  updated_at timestamptz not null default now(),
  unique (month, year)
);

drop trigger if exists finance_budgets_set_updated_at on public.finance_budgets;
create trigger finance_budgets_set_updated_at
  before update on public.finance_budgets
  for each row execute function public.set_updated_at();

create table if not exists public.finance_invoices (
  id uuid primary key default gen_random_uuid(),
  invoice_number text not null unique,
  charge_id uuid references public.finance_participant_charges (id),
  client_name text not null,
  client_email text,
  client_phone text,
  currency text not null default 'XAF',
  total_amount numeric(14, 2) not null check (total_amount >= 0),
  due_date date,
  status text not null default 'draft' check (status in ('draft', 'sent', 'paid', 'overdue', 'cancelled')),
  document_path text,
  created_by uuid references public.profiles (id),
  legacy_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

drop trigger if exists finance_invoices_set_updated_at on public.finance_invoices;
create trigger finance_invoices_set_updated_at
  before update on public.finance_invoices
  for each row execute function public.set_updated_at();

create table if not exists public.finance_invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.finance_invoices (id) on delete cascade,
  description text not null,
  quantity integer not null default 1 check (quantity > 0),
  unit_amount numeric(14, 2) not null check (unit_amount >= 0),
  sort_order integer not null default 0
);

create table if not exists public.finance_petty_cash_entries (
  id uuid primary key default gen_random_uuid(),
  entry_type text not null check (entry_type in ('in', 'out')),
  description text not null default '',
  currency text not null default 'XAF',
  amount numeric(14, 2) not null check (amount > 0),
  running_balance numeric(14, 2) not null,
  linked_expense_id uuid references public.finance_expenses (id),
  linked_income_id uuid references public.finance_income (id),
  entered_by uuid references public.profiles (id),
  legacy_id uuid,
  entry_date timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.finance_transaction_events (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  entity_type text not null,
  entity_id uuid not null,
  actor_id uuid references public.profiles (id),
  before_data jsonb,
  after_data jsonb,
  source_system text not null default 'bauhaven_admin' check (source_system in ('bauhaven_admin', 'bauhaven_ft')),
  created_at timestamptz not null default now()
);

create index if not exists finance_transaction_events_entity_idx on public.finance_transaction_events (entity_type, entity_id);

-- ---------------------------------------------------------------------------
-- 7. Legacy snapshots / staging (┬º5.7) - private, not client-readable at all.
--    One-time import scaffolding; not part of the ongoing application schema.
-- ---------------------------------------------------------------------------
create table if not exists public.ft_import_participants (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_users (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_income (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_expenses (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_loans (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_payment_accounts (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_budgets (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_invoices (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_petty_cash (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_attendance (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);
create table if not exists public.ft_import_audit_log (
  legacy_id uuid primary key,
  raw jsonb not null,
  imported_at timestamptz not null default now()
);

create table if not exists public.integration_ft_id_map (
  id uuid primary key default gen_random_uuid(),
  source_table text not null,
  legacy_id uuid not null,
  target_table text not null,
  target_id uuid not null,
  match_method text not null check (match_method in ('exact_email', 'exact_phone', 'reference_number', 'manual_review', 'unmatched_preserved')),
  matched_by uuid references public.profiles (id),
  created_at timestamptz not null default now(),
  unique (source_table, legacy_id)
);

create table if not exists public.finance_migration_batches (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  status text not null default 'in_progress' check (status in ('in_progress', 'completed', 'failed', 'rolled_back')),
  notes text
);

create table if not exists public.finance_migration_exceptions (
  id uuid primary key default gen_random_uuid(),
  batch_id uuid references public.finance_migration_batches (id),
  source_table text not null,
  legacy_id uuid,
  reason text not null,
  raw jsonb,
  resolved boolean not null default false,
  resolved_by uuid references public.profiles (id),
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- 8. Derived balances (┬º5.8) - a view, not a manually-editable column, so
--    "paid" is always computed from confirmed payment allocations, never
--    trusted as a stored boolean.
-- ---------------------------------------------------------------------------
create or replace view public.finance_participant_balances as
select
  c.id as charge_id,
  c.enrolment_id,
  c.legacy_participant_id,
  c.currency,
  c.amount_due,
  coalesce(sum(a.allocated_amount) filter (where p.status = 'confirmed'), 0) as amount_paid,
  c.amount_due - coalesce(sum(a.allocated_amount) filter (where p.status = 'confirmed'), 0) as outstanding_balance,
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
group by c.id, c.enrolment_id, c.legacy_participant_id, c.currency, c.amount_due, c.status, c.due_date;

-- NOTE: reversed/refunded payments are excluded from amount_paid by the
-- `filter (where p.status = 'confirmed')` clause above - a reversal doesn't
-- need its own negative-allocation row, it simply stops counting once its
-- payment's status moves off 'confirmed'.

-- ---------------------------------------------------------------------------
-- RLS: enabled here, but policies are intentionally NOT written in this
-- draft - they depend on the finance permission keys (finance.*.read/manage
-- etc., ┬º9.5 of the master prompt) which don't exist yet in `permissions`.
-- Adding RLS-enabled-but-policy-less tables would deny ALL access by
-- default (safe fail-closed default), which is correct for a draft that
-- isn't live yet, but this must not ship without real policies attached in
-- the same migration that actually gets applied.
-- ---------------------------------------------------------------------------
alter table public.finance_fee_plans enable row level security;
alter table public.finance_participant_charges enable row level security;
alter table public.finance_payments enable row level security;
alter table public.finance_payment_allocations enable row level security;
alter table public.finance_receipts enable row level security;
alter table public.finance_payment_accounts enable row level security;
alter table public.finance_expense_categories enable row level security;
alter table public.finance_income enable row level security;
alter table public.finance_expenses enable row level security;
alter table public.finance_loans enable row level security;
alter table public.finance_loan_repayments enable row level security;
alter table public.finance_budgets enable row level security;
alter table public.finance_invoices enable row level security;
alter table public.finance_invoice_items enable row level security;
alter table public.finance_petty_cash_entries enable row level security;
alter table public.finance_transaction_events enable row level security;
alter table public.ft_import_participants enable row level security;
alter table public.ft_import_users enable row level security;
alter table public.ft_import_income enable row level security;
alter table public.ft_import_expenses enable row level security;
alter table public.ft_import_loans enable row level security;
alter table public.ft_import_payment_accounts enable row level security;
alter table public.ft_import_budgets enable row level security;
alter table public.ft_import_invoices enable row level security;
alter table public.ft_import_petty_cash enable row level security;
alter table public.ft_import_attendance enable row level security;
alter table public.ft_import_audit_log enable row level security;
alter table public.integration_ft_id_map enable row level security;
alter table public.finance_migration_batches enable row level security;
alter table public.finance_migration_exceptions enable row level security;

-- No policies added yet - see the comment block above. This means every one
-- of these tables is currently unreadable/unwritable by any client role
-- once this migration is applied, until a follow-up migration adds the
-- permission-scoped policies alongside the new `finance.*` permission keys.
