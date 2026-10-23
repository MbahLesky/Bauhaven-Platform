-- Bauhaven Admin - one-time Super Admin bootstrap/recovery (Part B)
--
-- A singleton "claim" table: at most one row can ever exist (enforced by
-- the constant `singleton` primary key), so the bootstrap-super-admin Edge
-- Function can atomically check-and-claim in one INSERT - if a row already
-- exists, the insert fails with a unique-violation and the function refuses
-- to run again. This is what "disable the bootstrap path after first use"
-- actually means at the database level, rather than trusting the Edge
-- Function's own in-memory logic (which a retried/duplicated deploy could
-- bypass) or a repeatable script (explicitly forbidden by the master
-- prompt: "never a repeatable script that creates duplicates").
create table if not exists public.super_admin_bootstrap_state (
  singleton boolean primary key default true check (singleton),
  used_at timestamptz not null default now(),
  used_for_email citext not null,
  created_assignment_id uuid
);

alter table public.super_admin_bootstrap_state enable row level security;

-- No client policy at all, in either direction: this table is written
-- exactly once by the service-role Edge Function and is never meant to be
-- read or written by any authenticated session, including super_admin.
