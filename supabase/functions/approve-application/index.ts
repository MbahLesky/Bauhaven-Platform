// approve-application
//
// Privileged Bauhaven Admin operation: approves an admissions application
// and turns it into a real platform account. Follows the operation contract
// in the platform's API/Edge-Function technical document (approve-application
// entry) and the approval steps in 04_BAUHAVEN_DATABASE_SCHEMA.md section 15.2:
//   1. authenticate and authorize the reviewer (private.has_permission
//      ('applications.decide'), not just "is signed in").
//   2. lock/check application state.
//   3. detect/link identity safely (find-or-invite by email).
//   4. create the application_approvals record.
//   5. create the enrolment.
//   6. create/record the invitation.
//   7. append status history and audit event (status history happens
//      automatically via the applications_record_status_history trigger).
//   8. queue email (delegated to Supabase Auth's own invite email).
//   9. return a stable, idempotent result.
//
// Idempotency: application_id is the natural idempotency key (this matches
// the platform's own API contract note: "retries reuse enrolment and
// invitation state") - enforced by the unique indexes on
// application_approvals.application_id and enrolments.application_id, not by
// the generic idempotency_keys table (that table exists for other future
// functions - see supabase/migrations/0006_audit_and_idempotency.sql).
//
// Deploy with: supabase functions deploy approve-application
// Required secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (injected
// automatically for every Edge Function - never hardcode them).

// npm:, not jsr: - see invite-administrator's identical comment for why.
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

interface ApprovePayload {
  application_id: string;
  cohort_id?: string | null;
  assigned_role?: string;
  mentor_id?: string | null;
  start_date?: string | null;
  end_date?: string | null;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

// A brand-new applicant gets Supabase Auth's own invite email
// (inviteUserByEmail below) - that link doubles as their approval
// notification. Someone who *already* has a Bauhaven profile (a returning
// applicant, staff re-running this, etc.) gets no invite email at all,
// since none is needed - so without this, they'd never learn their
// application was approved. Best-effort only: a failure here must never
// undo or fail the approval itself, which has already fully succeeded by
// the time this is called.
async function sendApprovalEmail(email: string, name: string): Promise<void> {
  const apiKey = Deno.env.get('RESEND_API_KEY');
  if (!apiKey) return;
  try {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: 'Bauhaven <info@bauhaven.com>',
        to: [email],
        subject: 'Your Bauhaven application has been approved',
        html: `<p>Hi ${name || 'there'},</p>
               <p>Good news - your application to Bauhaven has been approved.</p>
               <p>Log in to your account to see your enrolment details.</p>
               <p>ÔÇö Bauhaven</p>`,
      }),
    });
  } catch {
    // Best-effort - see comment above.
  }
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

  // Client scoped to the caller's own JWT, used only to identify who is
  // calling. All privileged reads/writes below use the service-role client.
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

  let payload: ApprovePayload;
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
    .select('id, applicant_name, applicant_email, offering_id, status')
    .eq('id', payload.application_id)
    .maybeSingle();

  if (applicationError) {
    return jsonResponse({ error: `Failed to load application: ${applicationError.message}` }, 500);
  }
  if (!application) {
    return jsonResponse({ error: 'Application not found.' }, 404);
  }

  // Scoped to this application's offering, not a bare organisation-wide
  // check: has_permission_for()'s 'organisation'-scope branch still short-
  // circuits true for org-wide holders, while an offering-scoped
  // programme_manager/internship_coordinator now also passes for
  // applications within their own offering.
  //
  // Uses public.has_permission_for(p_user_id, ...) - migration 0015 -
  // rather than private.has_permission(), which reads auth.uid() from the
  // request's own JWT. Called through the service-role `admin` client (no
  // session JWT for the real caller), auth.uid() always resolves to null
  // there, and private.has_permission isn't exposed to PostgREST anyway -
  // both bugs together meant this permission check has always failed,
  // for every caller including super_admin, which surfaced as a generic
  // "Permission denied" 403 with no visible sign it was actually a wiring
  // bug. See migration 0015 and the audit doc for the live confirmation.
  const { data: canDecide, error: permError } = await admin.rpc('has_permission_for', {
    p_user_id: callerId,
    p_code: 'applications.decide',
    p_scope_type: 'offering',
    p_scope_id: application.offering_id,
  });
  if (permError || !canDecide) {
    return jsonResponse({ error: 'Permission denied: applications.decide required.' }, 403);
  }

  if (application.status === 'rejected' || application.status === 'withdrawn') {
    return jsonResponse(
      { error: `Application cannot be approved from status "${application.status}".` },
      409,
    );
  }

  // Idempotency check: an approval record for this application already
  // means it was approved before. Return the existing result rather than
  // redoing work or sending a second invitation email.
  const { data: existingApproval } = await admin
    .from('application_approvals')
    .select('id, enrolment_id')
    .eq('application_id', application.id)
    .maybeSingle();

  if (existingApproval) {
    const { data: existingEnrolment } = await admin
      .from('enrolments')
      .select('id, profile_id')
      .eq('id', existingApproval.enrolment_id)
      .maybeSingle();
    return jsonResponse({
      ok: true,
      alreadyApproved: true,
      applicationId: application.id,
      userId: existingEnrolment?.profile_id ?? null,
      enrolmentId: existingApproval.enrolment_id,
      invited: false,
    });
  }

  const email = application.applicant_email?.trim().toLowerCase();
  if (!email) {
    return jsonResponse({ error: 'Application has no email address on file.' }, 422);
  }

  // Find an existing profile/auth user for this email before inviting a new
  // one, so re-applicants and staff re-runs never create duplicate accounts.
  const { data: existingProfile } = await admin
    .from('profiles')
    .select('id')
    .ilike('email', email)
    .maybeSingle();

  let userId: string;
  let invited = false;

  if (existingProfile) {
    userId = existingProfile.id;
  } else {
    const { data: invitedUser, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
      data: { full_name: application.applicant_name ?? '' },
    });
    if (inviteError || !invitedUser?.user) {
      await admin.rpc('log_audit_event', {
        p_actor_id: callerId,
        p_action: 'application.approve_failed',
        p_entity_type: 'application',
        p_entity_id: application.id,
        p_before: null,
        p_after: null,
        p_outcome: 'failure',
        p_metadata: { reason: inviteError?.message ?? 'invite_failed' },
        p_request_id: null,
      });
      return jsonResponse({ error: `Failed to invite applicant: ${inviteError?.message}` }, 500);
    }
    userId = invitedUser.user.id;
    invited = true;
  }

  // Participant/Hub access comes from having an active `enrolments` row,
  // not from a `roles` grant - the roles table's catalogue (BAU-ADMIN-AUTH-001
  // section 5) only covers staff/admin roles. This function's first draft
  // granted a 'learner' role here; that's removed as a corrected
  // understanding of the v2.0 identity model, not a feature loss.

  const { data: enrolment, error: enrolmentError } = await admin
    .from('enrolments')
    .upsert(
      {
        profile_id: userId,
        application_id: application.id,
        offering_id: application.offering_id,
        cohort_id: payload.cohort_id ?? null,
        assigned_role: payload.assigned_role ?? 'Intern',
        mentor_id: payload.mentor_id ?? null,
        started_at: payload.start_date ?? null,
        status: 'pending_activation',
      },
      { onConflict: 'application_id' },
    )
    .select('id')
    .single();

  if (enrolmentError) {
    return jsonResponse({ error: `Failed to create enrolment: ${enrolmentError.message}` }, 500);
  }

  const { error: approvalError } = await admin.from('application_approvals').insert({
    application_id: application.id,
    decided_by: callerId,
    approved_offering_id: application.offering_id,
    approved_cohort_id: payload.cohort_id ?? null,
    enrolment_id: enrolment.id,
    assigned_role: payload.assigned_role ?? 'Intern',
    mentor_id: payload.mentor_id ?? null,
    start_date: payload.start_date ?? null,
    end_date: payload.end_date ?? null,
  });
  if (approvalError) {
    return jsonResponse({ error: `Approved but failed to record the decision: ${approvalError.message}` }, 500);
  }

  await admin.from('invitations').insert({
    application_id: application.id,
    enrolment_id: enrolment.id,
    email,
    status: invited ? 'sent' : 'accepted',
    sent_at: invited ? new Date().toISOString() : null,
    accepted_at: invited ? null : new Date().toISOString(),
  });

  const { error: updateError } = await admin
    .from('applications')
    .update({
      status: 'approved',
      assigned_reviewer_id: callerId,
    })
    .eq('id', application.id);

  if (updateError) {
    return jsonResponse({ error: `Approved but failed to update application status: ${updateError.message}` }, 500);
  }

  if (!invited) {
    // existingProfile branch - see sendApprovalEmail's comment for why.
    await sendApprovalEmail(email, application.applicant_name ?? '');
  }

  await admin.rpc('log_audit_event', {
    p_actor_id: callerId,
    p_action: 'application.approved',
    p_entity_type: 'application',
    p_entity_id: application.id,
    p_before: { status: application.status },
    p_after: { status: 'approved', enrolment_id: enrolment.id, user_id: userId },
    p_outcome: 'success',
    p_metadata: { invited },
    p_request_id: null,
  });

  return jsonResponse({
    ok: true,
    alreadyApproved: false,
    applicationId: application.id,
    userId,
    enrolmentId: enrolment.id,
    invited,
  });
});
