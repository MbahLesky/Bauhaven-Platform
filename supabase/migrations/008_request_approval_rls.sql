-- =========================================================
-- Requests: let an approval actually be recorded
-- =========================================================
--
-- `requests` had SELECT and INSERT policies and nothing else, and `request_approvals` had
-- SELECT and UPDATE but no INSERT. Together that made the approval side of the feature
-- impossible rather than merely unbuilt: no request could leave 'pending' by any route,
-- including an Admin's, and no approver row could be created to decide it with. Same
-- family as `004_submission_grading_rls.sql` and `005_finance_approval_rls.sql` — found
-- by building against the policies rather than reading them.
--
-- **What this migration does and does not enforce.** The quorum rule (a User's request
-- needs one Staff approval; a Staff's needs one Admin; an Admin's needs every *other*
-- Admin, unanimous; a single-Admin company auto-approves) lives in the application, as a
-- pure function with its own unit tests — see `src/lib/approval-quorum.ts` in
-- `bauhaven-admin-web`. Encoding it in SQL would mean a second copy of a rule that is
-- genuinely intricate, free to drift from the first, and the policies below are chosen so
-- the database still enforces the parts it can express cleanly:
--
--   * only Admin/Staff can create an approver row at all;
--   * nobody can be listed as an approver of their own request (the "every *other* Admin"
--     half of the quorum rule, which is the part with real teeth — an Admin must not be
--     able to sign off their own absence);
--   * only somebody already listed as a required approver can move the request's status,
--     so the set of approver rows is the gate on who decides;
--   * only `status` is writable on `requests` — dates, reason and requester are fixed
--     once submitted, exactly as they are for the student who wrote them.
--
-- The residual gap is stated plainly rather than papered over: a Staff member who creates
-- an approver row naming themselves on a *Staff* colleague's request would be allowed by
-- these policies, and is prevented by the application. Closing that in SQL needs a
-- `security definer` quorum helper, which is worth doing if approvals ever gain a second
-- client (Admin-native, M4) — at that point the rule should move into the database and the
-- TypeScript function should call it, the same way `auth_has_permission` works today.

-- ---------------------------------------------------------
-- request_approvals: create the rows an approval is recorded on
-- ---------------------------------------------------------

-- Lazily created when a Staff/Admin first opens a pending request — nothing creates them
-- at submission time, deliberately (see the Academy Requests feature). The table's
-- `unique (request_id, approver_id)` makes that safe to repeat.
create policy request_approvals_insert on request_approvals for insert
  with check (
    auth_is_admin_or_staff()
    -- Never an approver of your own request. This is the "every *other* Admin" clause,
    -- and the one piece of the quorum rule that has to hold even if the app is wrong.
    and approver_id <> (select r.requester_id from requests r where r.id = request_id)
  );

-- ---------------------------------------------------------
-- requests: let a decision land on the request itself
-- ---------------------------------------------------------

-- Only `status` moves. Everything else is what the requester wrote, and an approver
-- editing someone's stated dates or reason before approving them would make the record
-- of what was agreed untrue.
revoke update on requests from anon, authenticated;
grant update (status) on requests to authenticated;

create policy requests_decide on requests for update
  using (
    status = 'pending'
    and exists (
      select 1 from request_approvals ra
      where ra.request_id = requests.id and ra.approver_id = auth.uid()
    )
  )
  with check (
    status in ('approved', 'rejected')
    and exists (
      select 1 from request_approvals ra
      where ra.request_id = requests.id and ra.approver_id = auth.uid()
    )
  );
