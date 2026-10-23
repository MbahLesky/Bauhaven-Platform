// bootstrap-super-admin
//
// One-time, self-disabling recovery path for when NO super_admin account
// can be recovered any other way (BAUHAVEN_PHASE_4_5_AUTH_AND_FT_
// INTEGRATION_PROMPT.md Part B). This is deliberately the *last* resort:
// try Part A's password-recovery fix on an existing account first. Only
// reach for this if that's genuinely impossible (e.g. the only super_admin
// account's email is also lost/inaccessible).
//
// Explicitly NOT any of the patterns the master prompt forbids:
//   - not a public Flutter screen - it's a server-side-only Edge Function;
//   - not a service-role call from Flutter - the service role key never
//     leaves this function;
//   - not permanently unauthenticated - gated by BOOTSTRAP_SECRET, a
//     one-time secret set via `supabase secrets set BOOTSTRAP_SECRET=...`
//     (never committed, never hardcoded);
//   - not a hard-coded email/password - both are request parameters,
//     supplied out-of-band by the founder at the moment of use;
//   - not a repeatable script that creates duplicates - migration 0017's
//     `super_admin_bootstrap_state` is a singleton row (PK is a constant
//     `true`); the claim-insert below fails with a unique violation on any
//     second call, regardless of secret or payload.
//
// After first successful use, this function refuses every subsequent call
// (checked twice: once cheaply up front, once as the atomic claim at the
// end). As an extra step the founder should still run once this recovery
// is confirmed working: `supabase functions delete bootstrap-super-admin`
// and rotate BOOTSTRAP_SECRET, so the code path itself stops existing in
// the deployed project, not just the data flag.
//
// Deploy with: supabase functions deploy bootstrap-super-admin
// Then once, out of band: supabase secrets set BOOTSTRAP_SECRET=<a long random value>

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

interface BootstrapPayload {
  secret: string;
  email: string;
  full_name?: string;
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
  const bootstrapSecret = Deno.env.get('BOOTSTRAP_SECRET');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'Server misconfiguration: missing Supabase service credentials.' }, 500);
  }
  if (!bootstrapSecret) {
    // Refuses to run at all until the founder has deliberately set the
    // secret out of band - there is no usable default.
    return jsonResponse({ error: 'Bootstrap is not configured (BOOTSTRAP_SECRET unset).' }, 503);
  }

  let payload: BootstrapPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400);
  }

  if (!payload.secret || payload.secret !== bootstrapSecret) {
    return jsonResponse({ error: 'Invalid bootstrap secret.' }, 403);
  }

  const email = payload.email?.trim().toLowerCase();
  if (!email) {
    return jsonResponse({ error: 'email is required.' }, 400);
  }

  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Cheap up-front check (saves work on the common "already used" case) -
  // the real, race-safe enforcement is the claim-insert near the end.
  const { data: alreadyUsed } = await admin
    .from('super_admin_bootstrap_state')
    .select('used_at, used_for_email')
    .eq('singleton', true)
    .maybeSingle();
  if (alreadyUsed) {
    return jsonResponse(
      { error: `Bootstrap already used at ${alreadyUsed.used_at} for ${alreadyUsed.used_for_email}. This path is one-time only.` },
      409,
    );
  }

  const { data: superAdminRole, error: roleError } = await admin
    .from('roles')
    .select('id')
    .eq('code', 'super_admin')
    .maybeSingle();
  if (roleError || !superAdminRole) {
    return jsonResponse({ error: 'super_admin role not found in the roles catalogue.' }, 500);
  }

  const { data: existingProfile } = await admin
    .from('profiles')
    .select('id')
    .ilike('email', email)
    .maybeSingle();

  let userId: string;
  let createdNewUser = false;

  if (existingProfile) {
    userId = existingProfile.id;
  } else {
    const { data: invitedUser, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
      data: {
        full_name: payload.full_name ?? '',
        // Reuses the existing "needs password setup" screen/flow
        // (AuthController._onAuthEvent) rather than building a second one -
        // that flow tolerates this token not resolving to a real
        // admin_invitations row (it logs and continues to the password
        // screen regardless), since this account's real role grant is
        // created directly below, not through the normal invitation table.
        admin_invitation_token: 'bootstrap-super-admin',
      },
    });
    if (inviteError || !invitedUser?.user) {
      return jsonResponse({ error: `Failed to create the account: ${inviteError?.message}` }, 500);
    }
    userId = invitedUser.user.id;
    createdNewUser = true;
  }

  const { data: assignment, error: grantError } = await admin
    .from('user_role_assignments')
    .insert({
      user_id: userId,
      role_id: superAdminRole.id,
      assignment_type: 'permanent',
      scope_type: 'organisation',
      status: 'active',
      granted_by: null, // no human granter exists for a bootstrap recovery
    })
    .select('id')
    .single();
  if (grantError || !assignment) {
    return jsonResponse({ error: `Failed to create the super_admin assignment: ${grantError?.message}` }, 500);
  }

  // The atomic claim: this INSERT is the only thing that can ever disable
  // this function's ability to act again. If two requests somehow race
  // past the checks above, only one of these can succeed.
  const { error: claimError } = await admin.from('super_admin_bootstrap_state').insert({
    used_for_email: email,
    created_assignment_id: assignment.id,
  });
  if (claimError) {
    // Extremely unlikely (would mean a concurrent call won the race
    // between the up-front check and here) - the assignment above still
    // succeeded, so surface that rather than pretending nothing happened.
    return jsonResponse(
      {
        error: 'A concurrent bootstrap call already claimed this path, but this call also created a valid super_admin assignment - review both manually.',
        userId,
        assignmentId: assignment.id,
      },
      409,
    );
  }

  await admin.rpc('log_audit_event', {
    p_actor_id: null,
    p_action: 'super_admin.bootstrapped',
    p_entity_type: 'user_role_assignment',
    p_entity_id: assignment.id,
    p_before: null,
    p_after: { email, user_id: userId, created_new_user: createdNewUser },
    p_outcome: 'success',
    p_metadata: { note: 'One-time recovery path - see migration 0017.' },
  });

  return jsonResponse({
    ok: true,
    userId,
    assignmentId: assignment.id,
    createdNewUser,
    nextStep: createdNewUser
      ? 'An invite email was sent to set a password. If it does not arrive, use Forgot Password from the sign-in screen once signed in is attempted once.'
      : 'This email already had an account - sign in with its existing password, or use Forgot Password.',
  });
});
