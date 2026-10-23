-- Renumbered 2026-09-11: this was `0008_participant_platform_tables.sql` on MbahLesky/Bauhaven-admin `main`.
-- The finance/governance line had already used 0008-0028, so the participant files became 0029-0032 when the
-- two histories were merged. Already applied to keyaahfksbfigcdbbuda (confirmed by
-- docs/live-schema-snapshot.md) - do not re-run it there.
--
-- Bauhaven - Participant-facing platform tables (BAU-DB-002 sections 10-15)
--
-- These are the tables Hub needs that the shared project does not yet have:
-- attendance, notifications, announcements, digital resources, submission
-- files and the storage-object registry.
--
-- Every statement is idempotent. The live project was not introspectable when
-- this was written (no CLI, no credentials), and parts of this schema may
-- already exist from work outside these migrations, so nothing here assumes
-- absence.
--
-- Naming follows the LIVE database, not BAU-DB-002 where the two disagree:
--   * enrolments.profile_id   (the doc says participant_id)
--   * learning_projects       (the doc says projects; that name is taken by
--                              the website's public project showcase)
-- The live names win because the deployed RLS policies already reference them.

-- Enums ---------------------------------------------------------------------
-- Guarded individually: create type has no "if not exists" form.

do $$ begin
  create type public.attendance_session_status as enum
    ('draft', 'open', 'closed', 'cancelled');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.attendance_status as enum
    ('not_recorded', 'present', 'absent', 'late', 'excused');
exception when duplicate_object then null;
end $$;

do $$ begin
  create type public.notification_status as enum
    ('queued', 'sent', 'delivered', 'failed', 'read');
exception when duplicate_object then null;
end $$;

-- Storage object registry (BAU-DB-002 section 14.1) -------------------------
-- Metadata mirror of Supabase Storage. Files are referenced through this table
-- rather than by raw bucket path so that size, MIME type and classification
-- are recorded server-side and cannot be asserted by a client.

create table if not exists public.storage_objects (
  id                 uuid primary key default gen_random_uuid(),
  bucket_name        text not null,
  object_path        text not null unique,
  original_filename  text not null,
  mime_type          text not null,
  size_bytes         bigint not null check (size_bytes > 0),
  checksum           text,
  owner_profile_id   uuid references public.profiles(id) on delete set null,
  classification     text not null default 'confidential'
                     check (classification in
                       ('public', 'internal', 'confidential', 'highly_confidential')),
  uploaded_by        uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  deleted_at         timestamptz
);

create index if not exists storage_objects_owner_idx
  on public.storage_objects (owner_profile_id) where deleted_at is null;

-- Attendance (BAU-DB-002 section 11) ----------------------------------------

create table if not exists public.attendance_sessions (
  id            uuid primary key default gen_random_uuid(),
  offering_id   uuid references public.offerings(id) on delete cascade,
  cohort_id     uuid not null references public.cohorts(id) on delete cascade,
  title         text not null,
  session_type  text not null default 'class'
                check (session_type in
                  ('class', 'workshop', 'check_in', 'project', 'event')),
  starts_at     timestamptz not null,
  ends_at       timestamptz,
  location_text text,
  status        public.attendance_session_status not null default 'draft',
  method        text not null default 'manual',
  created_by    uuid references public.profiles(id) on delete set null,
  closed_at     timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at)
);

create index if not exists attendance_sessions_cohort_idx
  on public.attendance_sessions (cohort_id, starts_at desc);

create table if not exists public.attendance_records (
  id                    uuid primary key default gen_random_uuid(),
  attendance_session_id uuid not null
                        references public.attendance_sessions(id) on delete cascade,
  enrolment_id          uuid not null
                        references public.enrolments(id) on delete cascade,
  status                public.attendance_status not null default 'not_recorded',
  recorded_by           uuid references public.profiles(id) on delete set null,
  recorded_at           timestamptz not null default now(),
  note                  text,
  corrected_at          timestamptz,
  corrected_by          uuid references public.profiles(id) on delete set null,
  correction_reason     text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  unique (attendance_session_id, enrolment_id),
  -- A correction must say why. Attendance affects completion, so an unexplained
  -- edit is exactly the thing an auditor needs to be able to challenge.
  check (corrected_at is null or correction_reason is not null)
);

create index if not exists attendance_records_enrolment_idx
  on public.attendance_records (enrolment_id);

-- Notifications and announcements (BAU-DB-002 section 12) -------------------

create table if not exists public.announcements (
  id                 uuid primary key default gen_random_uuid(),
  title              text not null,
  body               text not null,
  audience_type      text not null default 'organisation'
                     check (audience_type in
                       ('organisation', 'offering', 'cohort', 'selected_users')),
  audience_id        uuid,
  publication_status public.publication_status not null default 'draft',
  publish_at         timestamptz,
  expires_at         timestamptz,
  created_by         uuid references public.profiles(id) on delete set null,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now(),
  -- Organisation-wide announcements have no audience id; every other kind must
  -- name its audience or it would silently address everyone.
  check (
    (audience_type = 'organisation' and audience_id is null)
    or (audience_type <> 'organisation' and audience_id is not null)
  )
);

create index if not exists announcements_audience_idx
  on public.announcements (audience_type, audience_id, publication_status);

create table if not exists public.notifications (
  id                  uuid primary key default gen_random_uuid(),
  recipient_id        uuid not null references public.profiles(id) on delete cascade,
  type                text not null,
  title               text not null,
  body                text not null,
  related_entity_type text,
  related_entity_id   uuid,
  channel             text not null default 'in_app'
                      check (channel in ('in_app', 'email', 'push')),
  status              public.notification_status not null default 'queued',
  scheduled_at        timestamptz,
  sent_at             timestamptz,
  delivered_at        timestamptz,
  read_at             timestamptz,
  provider_message_id text,
  failure_code        text,
  retry_count         integer not null default 0,
  created_at          timestamptz not null default now()
);

create index if not exists notifications_recipient_idx
  on public.notifications (recipient_id, created_at desc);

-- Unread badge counts run on every Hub app open; without this the count is a
-- sequential scan of the recipient's whole history.
create index if not exists notifications_unread_idx
  on public.notifications (recipient_id) where read_at is null;

-- Digital resources (BAU-DB-002 section 15.4) -------------------------------

create table if not exists public.digital_resources (
  id                     uuid primary key default gen_random_uuid(),
  title                  text not null,
  description            text,
  storage_object_id      uuid references public.storage_objects(id) on delete set null,
  external_url           text,
  visibility_scope_type  public.scope_type not null default 'organisation',
  visibility_scope_id    uuid,
  version                integer not null default 1,
  created_by             uuid references public.profiles(id) on delete set null,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now(),
  check (
    (visibility_scope_type = 'organisation' and visibility_scope_id is null)
    or (visibility_scope_type <> 'organisation' and visibility_scope_id is not null)
  ),
  -- A resource is either a stored file or an external link. Neither means an
  -- empty card in Hub; both is ambiguous about which one to open.
  check (
    (storage_object_id is not null and external_url is null)
    or (storage_object_id is null and external_url is not null)
  )
);

create index if not exists digital_resources_scope_idx
  on public.digital_resources (visibility_scope_type, visibility_scope_id);

create table if not exists public.task_resources (
  task_id     uuid not null references public.tasks(id) on delete cascade,
  resource_id uuid not null references public.digital_resources(id) on delete cascade,
  sort_order  integer not null default 0,
  primary key (task_id, resource_id)
);

-- Submission files (BAU-DB-002 section 10.6) --------------------------------

create table if not exists public.submission_files (
  submission_id     uuid not null references public.submissions(id) on delete cascade,
  storage_object_id uuid not null references public.storage_objects(id) on delete cascade,
  sort_order        integer not null default 0,
  primary key (submission_id, storage_object_id)
);

-- Policy documents and acceptances (BAU-DB-002 sections 5.4-5.5) ------------

create table if not exists public.policy_documents (
  id           uuid primary key default gen_random_uuid(),
  policy_key   text not null,
  version      text not null,
  title        text not null,
  content_url  text not null,
  effective_at timestamptz not null,
  is_required  boolean not null default true,
  created_at   timestamptz not null default now(),
  unique (policy_key, version)
);

create table if not exists public.policy_acceptances (
  id                 uuid primary key default gen_random_uuid(),
  profile_id         uuid not null references public.profiles(id) on delete cascade,
  policy_document_id uuid not null references public.policy_documents(id) on delete cascade,
  accepted_at        timestamptz not null default now(),
  source_application text not null default 'hub'
                     check (source_application in ('website', 'admin', 'hub')),
  metadata           jsonb not null default '{}'::jsonb,
  unique (profile_id, policy_document_id)
);

-- updated_at maintenance ----------------------------------------------------
-- Reuses the trigger function created in 0001. Guarded so this migration does
-- not fail on a project where 0001 named it differently.

do $$
declare
  t text;
begin
  if exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'set_updated_at' and n.nspname = 'public'
  ) then
    foreach t in array array[
      'attendance_sessions', 'attendance_records', 'announcements',
      'digital_resources'
    ] loop
      execute format(
        'drop trigger if exists %I_set_updated_at on public.%I', t, t);
      execute format(
        'create trigger %I_set_updated_at before update on public.%I
           for each row execute function public.set_updated_at()', t, t);
    end loop;
  end if;
end $$;
