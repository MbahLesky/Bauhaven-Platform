-- ============================================================================
-- Fixes a live production bug: bauhaven-website's public /apply form cannot
-- submit at all right now ("null value in column tracking_code... violates
-- not-null constraint"). Migration 0004 backfilled tracking_code for
-- existing rows and then locked the column NOT NULL, but never added a
-- default/trigger to keep generating it for new rows - every insert from
-- the website (which has never supplied this column) has been failing.
--
-- A plain column DEFAULT can't reference other columns of the same row
-- (id/created_at), so this uses the same BEFORE INSERT trigger pattern as
-- the rest of this schema. Formula matches 0004's one-time backfill exactly
-- ('REF-' || year || '-' || first 6 chars of id) so new codes stay visually
-- consistent with the ones already issued.
-- ============================================================================

create or replace function public.generate_application_tracking_code()
returns trigger
language plpgsql
as $$
begin
  if new.tracking_code is null then
    new.tracking_code := 'REF-' || to_char(coalesce(new.created_at, now()), 'YYYY') || '-' || substr(new.id::text, 1, 6);
  end if;
  return new;
end;
$$;

drop trigger if exists applications_generate_tracking_code on public.applications;
create trigger applications_generate_tracking_code
  before insert on public.applications
  for each row execute function public.generate_application_tracking_code();
