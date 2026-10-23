-- ============================================================================
-- Small additive patch found while mapping bauhaven_ft's rebuild onto the
-- canonical finance_* schema (0020/0021). finance_income/finance_expenses
-- were missing a transaction-date column and approved_at/voided_at/
-- override_reason - fields the FT app displays/filters on directly. See
-- BauhavenDocs/finance-migration/FT_REBUILD_DATA_LAYER_MAPPING.md ┬º3/┬º4.
--
-- Additive only: nullable or defaulted columns, no data loss. 0 rows exist
-- in either table as of this write, so there is nothing to backfill.
-- ============================================================================

alter table public.finance_income
  add column if not exists transaction_date date not null default current_date,
  add column if not exists approved_at timestamptz,
  add column if not exists voided_at timestamptz,
  add column if not exists override_reason text;

alter table public.finance_expenses
  add column if not exists transaction_date date not null default current_date,
  add column if not exists approved_at timestamptz,
  add column if not exists voided_at timestamptz,
  add column if not exists override_reason text;

-- Atomic balance adjustment, replacing the non-atomic read-modify-write
-- pattern (FirestoreService.updateAccountBalance in the FT app) with a
-- single UPDATE that relies on Postgres row-level locking instead of two
-- independent round trips from the client.
create or replace function public.finance_adjust_account_balance(
  p_account_id uuid, p_delta numeric
) returns void
language sql
security invoker
as $$
  update public.finance_payment_accounts
  set current_balance = current_balance + p_delta
  where id = p_account_id;
$$;

grant execute on function public.finance_adjust_account_balance(uuid, numeric) to authenticated;
