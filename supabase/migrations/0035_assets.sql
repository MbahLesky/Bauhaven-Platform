-- =============================================================================
-- 0035_assets.sql (also referenced as proposed/05)
-- =============================================================================
-- Adds `public.assets` for the Bauhaven physical/digital resource inventory.
--
-- View access: console admins (`public.is_admin`) and `assets.manage` holders.
-- Write access: `assets.manage` holders (Super Admin, Organisation Admin,
-- Asset Manager).
-- =============================================================================

create table if not exists public.assets (
  id          uuid primary key default gen_random_uuid(),
  name        text not null,
  type        text not null check (type in ('physical', 'digital')),
  status      text not null default 'fine'
              check (status in ('fine', 'needs_repair', 'retired')),
  assigned_to uuid references public.profiles(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted_at  timestamptz
);

create index if not exists assets_active_idx
  on public.assets (status, name) where deleted_at is null;

drop trigger if exists assets_set_updated_at on public.assets;
create trigger assets_set_updated_at
  before update on public.assets
  for each row execute function public.set_updated_at();

alter table public.assets enable row level security;

drop policy if exists assets_select_staff on public.assets;
create policy assets_select_staff on public.assets
  for select
  using (
    public.is_admin(auth.uid())
    or private.has_permission('assets.manage')
  );

drop policy if exists assets_write_managers on public.assets;
create policy assets_write_managers on public.assets
  for all
  using (private.has_permission('assets.manage'))
  with check (private.has_permission('assets.manage'));
