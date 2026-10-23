-- ============================================================================
-- Second live bug found while fixing the /apply submission failure (see
-- 0025's commit message for the first). `public.applications.status` is
-- actually plain `text` on the live table - it always has been, since the
-- table pre-dates this schema and 0004's
-- `add column if not exists status public.application_status ...` is a
-- no-op once a same-named column already exists, regardless of type. The
-- website writes lowercase free-text values ('pending', ...) that don't
-- correspond to the enum's uppercase members at all.
--
-- `record_application_status_change()` (0004) inserts new.status into
-- application_status_history.to_status, which IS strictly typed as the
-- application_status enum - so every insert/update from the website has
-- been failing at the trigger, not just the ones missing tracking_code.
-- A side-effect audit-logging trigger must never have the power to block
-- the primary action (accepting an application), so this makes it
-- defensive: normalize known website status strings to the enum, and
-- silently skip the history row (never raise) for anything that doesn't
-- map cleanly, rather than guessing.
--
-- The deeper issue - applications.status being untyped text at all,
-- inconsistent with the enum-typed column every other part of this schema
-- assumes - is NOT fixed here. Retyping a live column with real data needs
-- its own careful migration (normalize existing values first, confirm
-- nothing else silently depends on the current loose typing). Flagged in
-- BauhavenDocs/website-seo/APPLY_FORM_FIX.md, not fixed blind.
-- ============================================================================

create or replace function public.record_application_status_change()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_from public.application_status;
  v_to public.application_status;
begin
  begin
    v_to := upper(new.status::text)::public.application_status;
  exception when invalid_text_representation then
    v_to := case lower(new.status::text)
      when 'pending' then 'SUBMITTED'
      when 'submitted' then 'SUBMITTED'
      when 'reviewing' then 'UNDER_REVIEW'
      when 'under_review' then 'UNDER_REVIEW'
      when 'approved' then 'ACCEPTED'
      when 'accepted' then 'ACCEPTED'
      when 'rejected' then 'REJECTED'
      when 'declined' then 'REJECTED'
      when 'expired' then 'EXPIRED'
      else null
    end;
  end;

  -- Unrecognized status text: don't block the insert/update, just skip
  -- logging this transition rather than raising or guessing.
  if v_to is null then
    return new;
  end if;

  if tg_op = 'INSERT' then
    insert into public.application_status_history (application_id, from_status, to_status, actor_id, reason)
    values (new.id, null, v_to, auth.uid(), new.decision_reason);
  elsif tg_op = 'UPDATE' and old.status is distinct from new.status then
    begin
      v_from := upper(old.status::text)::public.application_status;
    exception when invalid_text_representation then
      v_from := null;
    end;
    insert into public.application_status_history (application_id, from_status, to_status, actor_id, reason)
    values (new.id, v_from, v_to, auth.uid(), new.decision_reason);
  end if;

  return new;
end;
$$;
