// accept-admin-invitation
//
// Called by the Flutter app right after a newly-invited administrator's
// first successful sign-in (see AuthController - it checks the signed-in
// user's metadata for a pending `admin_invitation_token` and calls this
// automatically, rather than requiring a separate custom deep link on top
// of Supabase's own invite-email link). Also accepts an explicit `token`
// in the body for a future direct-link flow.
//
// Steps (BAU-UML section 10 "Accept administrator invitation"):
//   1. authenticate the caller;
//   2. resolve and validate the invitation (not expired, not revoked, not
//      already accepted, email matches the caller);
//   3. create the role assignment (active if valid_from has passed,
//      otherwise pending);
//   4. create an empty staff_profiles row for the invitee to complete;
//   5. mark the invitation accepted;
//   6. audit log.
//
// Idempotent: calling twice for an already-accepted invitation returns the
// existing result rather than erroring or double-granting.

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest('SHA-256', data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('');
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'Server misconfiguration: missing Supabase service credentials.' }, 500);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'Missing Authorization header.' }, 401);
  }

  const callerClient: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse({ error: 'Invalid or expired session.' }, 401);
  }
  const caller = userData.user;

  let rawToken: string | undefined;
  try {
    const body = await req.json();
    rawToken = body?.token;
  } catch {
    // no body is fine - fall through to metadata below
  }
  rawToken ??= caller.user_metadata?.admin_invitation_token as string | undefined;
  if (!rawToken) {
    return jsonResponse({ error: 'No invitation token provided or found on this account.' }, 400);
  }

  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const tokenHash = await sha256Hex(rawToken);
  const { data: invitation, error: invitationError } = await admin
    .from('admin_invitations')
    .select('*')
    .eq('token_hash', tokenHash)
    .maybeSingle();

  if (invitationError) {
    return jsonResponse({ error: `Failed to load invitation: ${invitationError.message}` }, 500);
  }
  if (!invitation) {
    return jsonResponse({ error: 'Invitation not found or invalid.' }, 404);
  }
  if (invitation.status === 'accepted') {
    return jsonResponse({ ok: true, alreadyAccepted: true });
  }
  if (invitation.status === 'revoked') {
    return jsonResponse({ error: 'This invitation has been revoked.' }, 409);
  }
  if (new Date(invitation.expires_at) < new Date()) {
    await admin.from('admin_invitations').update({ status: 'expired' }).eq('id', invitation.id);
    return jsonResponse({ error: 'This invitation has expired.' }, 409);
  }
  if (invitation.email.toLowerCase() !== (caller.email ?? '').toLowerCase()) {
    return jsonResponse({ error: 'This invitation was issued to a different email address.' }, 403);
  }

  const isActive = new Date(invitation.access_valid_from) <= new Date();
  const { error: grantError } = await admin.from('user_role_assignments').insert({
    user_id: caller.id,
    role_id: invitation.role_id,
    assignment_type: invitation.assignment_type,
    scope_type: invitation.scope_type,
    scope_id: invitation.scope_id,
    valid_from: invitation.access_valid_from,
    valid_until: invitation.access_valid_until,
    status: isActive ? 'active' : 'pending',
    granted_by: invitation.issued_by,
  });
  if (grantError) {
    return jsonResponse({ error: `Failed to create role assignment: ${grantError.message}` }, 500);
  }

  await admin.from('staff_profiles').upsert({ profile_id: caller.id }, { onConflict: 'profile_id', ignoreDuplicates: true });

  await admin
    .from('admin_invitations')
    .update({ status: 'accepted', accepted_at: new Date().toISOString(), accepted_user_id: caller.id })
    .eq('id', invitation.id);

  await admin.rpc('log_audit_event', {
    p_actor_id: caller.id,
    p_action: 'admin_invitation.accepted',
    p_entity_type: 'admin_invitation',
    p_entity_id: invitation.id,
    p_before: null,
    p_after: { status: isActive ? 'active' : 'pending' },
    p_outcome: 'success',
    p_metadata: {},
  });

  return jsonResponse({ ok: true, alreadyAccepted: false, assignmentStatus: isActive ? 'active' : 'pending' });
});
