-- Bauhaven Admin - fix a critical, previously-undetected bug: the
-- approve-application and invite-administrator Edge Functions have never
-- been able to succeed for anyone, including super_admin.
--
-- Both call `admin.rpc('has_permission', {...})` using the service-role
-- client. Two independent problems compound:
--   1. `private.has_permission()` reads `auth.uid()` internally. The
--      service-role client presents the service_role JWT itself as the
--      caller (it has no `sub` claim - decoded and confirmed live), so
--      `auth.uid()` resolves to null in that context regardless of who is
--      really calling the Edge Function.
--   2. `private.has_permission` is not exposed to PostgREST at all - only
--      `public`-schema functions are (confirmed live: POST
--      /rest/v1/rpc/has_permission with the service-role key returns
--      PGRST202 "Could not find the function public.has_permission").
-- Both Edge Functions swallow that RPC error into a generic "Permission
-- denied" 403, so the failure looked like an authorisation problem instead
-- of a wiring bug - it was never visible from the UI as anything other
-- than "Approve doesn't work."
--
-- Fix: add an explicit-user-id counterpart in the `public` schema, mirroring
-- the pattern already used by `public.is_admin(uid)` and
-- `public.log_audit_event(p_actor_id, ...)` for exactly this situation
-- (privileged code with no session JWT, but a caller id resolved another
-- way - here, from the caller's own JWT via `callerClient.auth.getUser()`
-- inside the Edge Function). Restricted to service_role so it can't be used
-- by a signed-in user to probe another user's permissions.

create or replace function public.has_permission_for(
  p_user_id uuid,
  p_code text,
  p_scope_type text default 'organisation',
  p_scope_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = public, private, pg_temp
as $$
  select exists (
    select 1
    from public.user_role_assignments ura
    join public.roles r on r.id = ura.role_id
    join public.role_permissions rp on rp.role_id = r.id
    join public.permissions p on p.id = rp.permission_id
    where ura.user_id = p_user_id
      and p.code = p_code
      and public.is_assignment_active(ura)
      and (
        ura.scope_type = 'organisation'
        or (ura.scope_type = p_scope_type and ura.scope_id = p_scope_id)
      )
  );
$$;

comment on function public.has_permission_for(uuid, text, text, uuid) is
  'Explicit-user-id counterpart to private.has_permission(), for callers with no session JWT in context (Edge Functions authenticated as service_role). Exposed to PostgREST so those functions can call it via RPC. Restricted to service_role - never call this with an untrusted client-supplied user id.';

revoke all on function public.has_permission_for(uuid, text, text, uuid) from public;
revoke all on function public.has_permission_for(uuid, text, text, uuid) from anon, authenticated;
grant execute on function public.has_permission_for(uuid, text, text, uuid) to service_role;
