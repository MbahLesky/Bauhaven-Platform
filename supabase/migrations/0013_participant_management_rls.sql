-- Bauhaven Admin - allow authorised participant-management updates
--
-- Migration 0007 deliberately left `enrolments` with no client UPDATE
-- policy at all, on the assumption every write went through
-- approve-application. Phase 3 adds participant suspend/reactivate
-- (FR-ADM-PEO-005) directly from the People screen, so a scoped UPDATE
-- policy is needed now - status/reason only, gated by `participants.manage`.

drop policy if exists enrolments_update_participant_management on public.enrolments;
create policy enrolments_update_participant_management on public.enrolments
  for update
  using (private.has_permission('participants.manage'))
  with check (private.has_permission('participants.manage'));
