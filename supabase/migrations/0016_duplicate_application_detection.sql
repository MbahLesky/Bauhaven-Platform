-- Bauhaven Admin - duplicate application detection (FR-ADM-APP-013)
--
-- `applications.duplicate_flag`/`duplicate_reason` have existed since
-- migration 0004 and the detail screen already renders a banner for them
-- (application_detail_screen.dart) - nothing has ever set them. Applicants
-- submit through the public bauhaven-website form (applications_insert_public,
-- unauthenticated), so detection has to happen in the database itself via a
-- trigger, not in admin-side Flutter code that never runs at submission time.
--
-- Flags, never blocks: a genuine repeat applicant (e.g. re-applying to a
-- different offering, or after a prior rejection) is a real, valid case the
-- doc explicitly wants surfaced to a human reviewer, not silently rejected.

create or replace function public.flag_duplicate_application()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  match_count integer;
  match_codes text;
begin
  if new.applicant_email is null or new.applicant_email::text = '' then
    return new;
  end if;

  select count(*), string_agg(tracking_code, ', ' order by created_at desc)
  into match_count, match_codes
  from public.applications
  where lower(applicant_email::text) = lower(new.applicant_email::text)
    and id <> new.id;

  if match_count > 0 then
    new.duplicate_flag := true;
    new.duplicate_reason := format(
      'Matching email found on %s prior application(s): %s',
      match_count,
      match_codes
    );
  end if;

  return new;
end;
$$;

drop trigger if exists applications_flag_duplicate on public.applications;
create trigger applications_flag_duplicate
  before insert on public.applications
  for each row execute function public.flag_duplicate_application();

-- One-time backfill: flag existing rows against the same rule so history
-- isn't silently exempt from a check that only fires on new inserts going
-- forward.
with dupes as (
  select a.id, count(*) - 1 as match_count,
         string_agg(b.tracking_code, ', ' order by b.created_at desc) filter (where b.id <> a.id) as match_codes
  from public.applications a
  join public.applications b on lower(b.applicant_email::text) = lower(a.applicant_email::text)
  where a.applicant_email::text <> ''
  group by a.id
  having count(*) > 1
)
update public.applications a
set duplicate_flag = true,
    duplicate_reason = format('Matching email found on %s prior application(s): %s', d.match_count, d.match_codes)
from dupes d
where a.id = d.id
  and a.duplicate_flag = false;
