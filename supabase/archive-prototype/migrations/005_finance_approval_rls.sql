-- Bauhaven Platform — an Admin can approve a finance record, and nothing else
-- Depends on: 002_row_level_security.sql
--
-- Found while building the Finance screen in bauhaven-admin-web.
--
-- `002` gave `finance_records` a SELECT and an INSERT policy and no UPDATE, with the
-- comment: "No update policy at all: append-only means corrections are new rows
-- (corrects_id), never edits." That reasoning is correct and is preserved here — but it
-- also made feature #21 ("Finance Record: approve/confirm", Admin only, Must)
-- unimplementable, and left three columns permanently dead:
--
--   status text not null default 'pending' check (status in ('pending','approved'))
--   approved_by uuid references users(id)
--   approved_at timestamptz
--
-- A row can only ever be inserted, and `finance_insert` has no WITH CHECK on `status`,
-- so the *only* reachable states were "pending forever" or "inserted pre-approved by
-- whoever recorded it" — which is precisely the separation of duties the three-person
-- payer/recorder/approver chain exists to enforce. Nullable `approved_by` and
-- `approved_at` alongside a `default 'pending'` status only make sense as a lifecycle:
-- insert pending, then transition. That transition is an UPDATE.
--
-- Rejected alternative: modelling approval as an INSERT with `corrects_id` pointing at
-- the pending row. `corrects_id` means "this fixes a mistake in that row", and an
-- approval is not a correction — it's a decision *about* a transaction that is not in
-- error. It would also restate the money on a second row (inviting the two to disagree),
-- move `created_at` off the transaction date onto the approval date, and require copying
-- `recorded_by` from someone else's row. The columns above are the schema's own answer.
--
-- =========================================================================
-- The guarantee this migration keeps
-- =========================================================================
--
-- Append-only is about the *money*: an amount, description, type, or payer that was
-- wrong must be corrected by a new row, never edited away. Two mechanisms together make
-- that true even for an Admin, rather than merely conventional:
--
--   1. Column-level privileges — `status`, `approved_by` and `approved_at` are the only
--      updatable columns on the table. `amount_minor`, `description`, `type`,
--      `payer_id`, `payer_name`, `recorded_by`, `corrects_id` and `created_at` cannot be
--      written by any UPDATE from an app session, so an edited amount is refused by
--      Postgres before RLS is even consulted.
--
--   2. The policy below — restricted to Admins, to rows that are still pending, and to a
--      result that is approved and stamped with the caller's own id.
--
-- Net effect: exactly one UPDATE is possible against this table — pending → approved, by
-- an Admin, naming themselves. Everything else is still insert-only.

-- Supabase's default setup grants table-wide DML on public tables to `anon` and
-- `authenticated`; RLS is what gates it. Narrowing the UPDATE grant to three columns is
-- safe and cannot regress anything: with no UPDATE policy in `002`, no UPDATE succeeded
-- against this table in the first place. `service_role` is left alone deliberately — it
-- bypasses RLS by design and is not an app session.
revoke update on finance_records from anon, authenticated;
grant update (status, approved_by, approved_at) on finance_records to authenticated;

-- USING decides which rows may be touched; WITH CHECK decides what the row may become.
-- Both are needed, and for the reason `003` recorded: USING alone answers only the first
-- question. Here USING confines approval to pending rows — which also makes approval
-- idempotent-by-refusal, since a second approver matches zero rows rather than
-- overwriting the first Admin's name — and WITH CHECK forbids using this policy to
-- un-approve something or to credit the decision to another Admin.
create policy finance_approve on finance_records for update
  using (auth_is_admin() and status = 'pending')
  with check (
    auth_is_admin()
    and status = 'approved'
    and approved_by = auth.uid()
  );

-- Note: approval is a *single* Admin, not a quorum. `finance_records` carries one
-- nullable `approved_by`; the multi-approver flow described for absence Requests lives in
-- its own `request_approvals` table with a unique (request_id, approver_id) precisely
-- because that flow needs several approvers and this one does not. Two mechanisms, not
-- one — see Bauhaven-Database-Schema.md.
