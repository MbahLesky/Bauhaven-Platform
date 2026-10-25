-- 0040_fcm_device_tokens.sql
-- Store Firebase Cloud Messaging (FCM) device registration tokens for Web (and Mobile) Push Notifications.

create table if not exists public.fcm_device_tokens (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  token text not null,
  platform text not null default 'web' check (platform in ('web', 'android', 'ios')),
  device_info jsonb default '{}'::jsonb,
  last_used_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint uq_fcm_device_tokens_profile_token unique (profile_id, token)
);

create index if not exists idx_fcm_device_tokens_profile on public.fcm_device_tokens (profile_id);
create index if not exists idx_fcm_device_tokens_token on public.fcm_device_tokens (token);

-- Enable RLS
alter table public.fcm_device_tokens enable row level security;

-- 1. Users can select their own tokens
create policy fcm_device_tokens_select_own on public.fcm_device_tokens
  for select to authenticated
  using (profile_id = auth.uid());

-- 2. Users can insert their own tokens
create policy fcm_device_tokens_insert_own on public.fcm_device_tokens
  for insert to authenticated
  with check (profile_id = auth.uid());

-- 3. Users can update their own tokens
create policy fcm_device_tokens_update_own on public.fcm_device_tokens
  for update to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- 4. Users can delete their own tokens (e.g. on logout)
create policy fcm_device_tokens_delete_own on public.fcm_device_tokens
  for delete to authenticated
  using (profile_id = auth.uid());

-- Service role full access
create policy fcm_device_tokens_service_role on public.fcm_device_tokens
  for all to service_role
  using (true)
  with check (true);

-- Grant privileges
grant select, insert, update, delete on public.fcm_device_tokens to authenticated;
grant all on public.fcm_device_tokens to service_role;

-- Helper RPC for registering/updating a device token smoothly
create or replace function public.register_fcm_token(
  p_token text,
  p_platform text default 'web',
  p_device_info jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    return jsonb_build_object('success', false, 'error', 'Authentication required.');
  end if;

  if p_token is null or trim(p_token) = '' then
    return jsonb_build_object('success', false, 'error', 'Token is required.');
  end if;

  insert into public.fcm_device_tokens (profile_id, token, platform, device_info, last_used_at, updated_at)
  values (v_uid, trim(p_token), p_platform, p_device_info, now(), now())
  on conflict (profile_id, token) do update
  set last_used_at = now(),
      device_info = coalesce(excluded.device_info, fcm_device_tokens.device_info),
      updated_at = now();

  return jsonb_build_object('success', true);
end;
$$;

comment on function public.register_fcm_token is 'Registers or refreshes an FCM device push token for the authenticated user.';
grant execute on function public.register_fcm_token to authenticated;
