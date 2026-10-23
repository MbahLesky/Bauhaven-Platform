// resend-invitation
//
// FR-ADM-APP-012. Re-sends the participant invitation for an already-
// approved application, for the case where the applicant never received or
// lost the original email. Follows the same structure as
// approve-application: caller-JWT identity resolution, service-role reads/
// writes, an explicit scoped permission check via
// public.has_permission_for() (migration 0015 - see approve-application's
// comments for why that function exists rather than calling
// private.has_permission()/admin.rpc('has_permission') directly).
//
// Does not create a second Supabase Auth user or a second enrolment - it
// only re-triggers delivery for the invitation row approve-application
// already created (unique per application_id).
//
// Deploy with: supabase functions deploy resend-invitation

import { createClient, type SupabaseClient } from 'jsr:@supabase/supabase-js@2';

interface ResendPayload {
  application_id: string;
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
  const callerId = userData.user.id;

  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let payload: ResendPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400);
  }
  if (!payload.application_id) {
    return jsonResponse({ error: 'application_id is required.' }, 400);
  }

  const { data: application, error: applicationError } = await admin
    .from('applications')
    .select('id, applicant_email, offering_id, status')
    .eq('id', payload.application_id)
    .maybeSingle();
  if (applicationError) {
    return jsonResponse({ error: `Failed to load application: ${applicationError.message}` }, 500);
  }
  if (!application) {
    return jsonResponse({ error: 'Application not found.' }, 404);
  }
  if (application.status !== 'approved') {
    return jsonResponse({ error: 'Only an approved application has an invitation to resend.' }, 409);
  }

  const { data: canDecide, error: permError } = await admin.rpc('has_permission_for', {
    p_user_id: callerId,
    p_code: 'applications.decide',
    p_scope_type: 'offering',
    p_scope_id: application.offering_id,
  });
  if (permError || !canDecide) {
    return jsonResponse({ error: 'Permission denied: applications.decide required.' }, 403);
  }

  const { data: invitation, error: invitationError } = await admin
    .from('invitations')
    .select('id, email, status, attempt_count')
    .eq('application_id', application.id)
    .maybeSingle();
  if (invitationError) {
    return jsonResponse({ error: `Failed to load invitation: ${invitationError.message}` }, 500);
  }
  if (!invitation) {
    return jsonResponse({ error: 'No invitation record exists for this application.' }, 404);
  }
  if (invitation.status === 'accepted') {
    return jsonResponse({ error: 'This applicant has already accepted their invitation.' }, 409);
  }
  if (invitation.status === 'revoked') {
    return jsonResponse({ error: 'This invitation was revoked and cannot be resent.' }, 409);
  }

  const email = (invitation.email ?? application.applicant_email)?.trim().toLowerCase();
  if (!email) {
    return jsonResponse({ error: 'No email address on file to resend to.' }, 422);
  }

  // Re-sends the real invite email via Supabase Auth's own mailer (the same
  // mechanism approve-application used originally) - deliberately not using
  // admin.generateLink(), which only returns a link and never sends
  // anything, and would have made this button silently do nothing.
  //
  // Known Supabase Auth limitation (supabase/auth#2180): inviting an email
  // that already has *any* auth user - even a still-unconfirmed one from
  // the original invite - can fail with "already been registered" rather
  // than actually resending. When that happens this returns the real error
  // instead of pretending to have succeeded; the admin can tell the
  // applicant to use "Forgot password" on the sign-in screen instead, which
  // sends a genuine, working recovery email through this app's existing
  // flow (auth_controller.dart's sendPasswordReset).
  const { error: inviteError } = await admin.auth.admin.inviteUserByEmail(email);
  if (inviteError) {
    return jsonResponse(
      {
        error: `Could not resend the invitation: ${inviteError.message}. If this applicant's account already exists, ask them to use "Forgot password" on the sign-in screen instead.`,
      },
      502,
    );
  }

  const { error: updateError } = await admin
    .from('invitations')
    .update({
      status: 'sent',
      sent_at: new Date().toISOString(),
      attempt_count: (invitation.attempt_count ?? 0) + 1,
    })
    .eq('id', invitation.id);
  if (updateError) {
    return jsonResponse({ error: `Resent but failed to update invitation record: ${updateError.message}` }, 500);
  }

  await admin.rpc('log_audit_event', {
    p_actor_id: callerId,
    p_action: 'invitation.resent',
    p_entity_type: 'application',
    p_entity_id: application.id,
    p_before: null,
    p_after: { status: 'sent' },
    p_outcome: 'success',
    p_metadata: { email },
    p_request_id: null,
  });

  return jsonResponse({ ok: true, email });
});
