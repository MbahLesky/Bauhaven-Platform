-- Bauhaven Admin - extensions, enums, shared functions
--
-- Aligned with bauhaven-admin/docs/04_BAUHAVEN_DATABASE_SCHEMA.md ("BAU-DB-001",
-- prepared 2026-07-18), which is the coordinated target schema for the whole
-- platform. That document explicitly says it is a *target*, not a claim that
-- the live Supabase project already matches it - run `supabase db pull` and
-- reconcile before applying (see supabase/README.md). This migration set
-- only builds the slice of that target schema the Admissions MVP needs
-- (identity/RBAC + applications + approval/invitation/enrolment), following
-- the "Migration Sequence Recommendation" in section 18 of that document.

create extension if not exists pgcrypto;
create extension if not exists citext;
create extension if not exists pg_trgm;

-- application_status includes 'clarification_requested', matching
-- 04_BAUHAVEN_DATABASE_SCHEMA.md section 3 and
-- 01_BAUHAVEN_INTERFACE_DESIGN.md section 4.5 ("Canonical status groups").
-- This is the authoritative 8-value set - it supersedes the 6/7-value
-- variants found elsewhere in the older docx planning set (see the final
-- completion report for the full contradiction list).
do $$
begin
  -- 'pending' is not part of the canonical vocabulary (see
  -- docs/01_BAUHAVEN_INTERFACE_DESIGN.md section 4.5) but is kept as an
  -- accepted legacy value: the live `applications` table already has 83
  -- rows with status='pending', written by bauhaven-website's public
  -- application form (Apply.js) before this migration ever ran. Rejecting
  -- that value here would break the live public form's inserts and this
  -- migration's own status-history trigger on the very next website
  -- submission. Treat it as a synonym for 'submitted' in the UI.
  if not exists (select 1 from pg_type where typname = 'application_status') then
    create type public.application_status as enum (
      'draft', 'pending', 'submitted', 'under_review', 'clarification_requested',
      'waitlisted', 'approved', 'rejected', 'withdrawn'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'invitation_status') then
    create type public.invitation_status as enum (
      'queued', 'sent', 'delivered', 'failed', 'accepted', 'expired', 'revoked'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'enrolment_status') then
    create type public.enrolment_status as enum (
      'pending_activation', 'active', 'paused', 'completed', 'withdrawn', 'cancelled'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'publication_status') then
    create type public.publication_status as enum (
      'draft', 'in_review', 'scheduled', 'published', 'archived'
    );
  end if;

  if not exists (select 1 from pg_type where typname = 'profile_status') then
    create type public.profile_status as enum (
      'pending', 'active', 'suspended', 'deactivated'
    );
  end if;
end $$;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- Schema for privilege-check helper functions. Nothing in this schema is
-- exposed via PostgREST; it exists purely so RLS policies (0007) can call
-- SECURITY DEFINER checks without recursing back through RLS on the tables
-- those checks themselves query - the standard Supabase pattern, and the
-- exact one specified in the Row-Level-Security Technical Foundation
-- document surfaced while researching this schema.
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
