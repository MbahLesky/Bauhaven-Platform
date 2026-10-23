-- Bauhaven Admin - backfill offerings from live application data
--
-- The live `applications` table has 83 real rows using a free-text
-- `program` column with 5 distinct values (bootcamp-program, career-tracks,
-- internship-program, course-training, holiday-program) and no offerings
-- table existed before this migration set. This is a best-effort
-- reconciliation, not authoritative product data: it seeds one `offerings`
-- row per distinct live `program` value so `applications.offering_id` can
-- be populated and the approval workflow's offering/cohort pickers aren't
-- empty for real, already-submitted applications. A human should review
-- and correct these titles/types once the Offerings module is actually
-- built - see supabase/README.md backlog.

insert into public.offerings (offering_type, title, slug, publication_status)
select
  case program
    when 'bootcamp-program' then 'bootcamp'
    when 'internship-program' then 'internship'
    when 'course-training' then 'course'
    when 'holiday-program' then 'holiday_program'
    else 'program'
  end,
  initcap(replace(program, '-', ' ')),
  program,
  'published'
from (select distinct program from public.applications where program is not null) distinct_programs
on conflict (slug) do nothing;

update public.applications a
set offering_id = o.id
from public.offerings o
where a.offering_id is null
  and a.program is not null
  and o.slug = a.program;
