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
function renderApprovalHtml(name: string): string {
  const safeName = name ? name : 'there';
  const portalUrl = Deno.env.get('ACADEMY_PORTAL_URL') || 'https://academy.bauhaven.com';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Your Bauhaven Application is Approved</title>
</head>
<body style="margin: 0; padding: 0; width: 100% !important; background-color: #F8F8F8; font-family: 'Archivo', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; -webkit-font-smoothing: antialiased; color: #1E1E1E;">
  <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #F8F8F8; margin: 0; padding: 32px 16px;">
    <tr>
      <td align="center" valign="top">
        <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="max-width: 580px; background-color: #FFFFFF; border-radius: 8px; border: 1px solid #EAEAEA; overflow: hidden; box-shadow: 0 2px 6px rgba(0,0,0,0.03);">
          <tr>
            <td style="height: 5px; background: #D72638; background: linear-gradient(90deg, #D72638 0%, #F26B3B 25%, #FED500 50%, #54BE8D 75%, #26AAD1 100%);"></td>
          </tr>
          <tr>
            <td style="padding: 32px 36px 20px 36px; border-bottom: 1px solid #F3F3F3;">
              <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
                <tr>
                  <td>
                    <span style="font-family: 'Montserrat', Helvetica, Arial, sans-serif; font-size: 22px; font-weight: 800; letter-spacing: 1.5px; color: #1E1E1E; text-transform: uppercase;">BAUHAVEN</span>
                    <span style="display: block; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; color: #888888; margin-top: 3px;">Technology &amp; Vocational Center</span>
                  </td>
                  <td align="right" valign="middle">
                    <span style="display: inline-block; padding: 4px 10px; background-color: #EBF8F2; color: #1B6E44; font-size: 11px; font-weight: 700; border-radius: 4px; text-transform: uppercase; letter-spacing: 0.5px; border: 1px solid #D1F0E0;">Approved</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding: 36px 36px 28px 36px;">
              <h1 style="font-family: 'Montserrat', Helvetica, Arial, sans-serif; font-size: 22px; font-weight: 800; color: #1E1E1E; margin: 0 0 16px 0; line-height: 1.3;">
                Congratulations, ${safeName}!
              </h1>
              <p style="font-size: 15px; line-height: 1.6; color: #3E3E3E; margin: 0 0 20px 0;">
                Great news — your application to Bauhaven has been approved. Your enrolment is now active and ready.
              </p>
              <table role="presentation" border="0" cellpadding="0" cellspacing="0" style="margin: 28px 0 20px 0;">
                <tr>
                  <td align="center" style="border-radius: 6px; background-color: #D72638;">
                    <a href="${portalUrl}" target="_blank" style="display: inline-block; padding: 14px 34px; font-family: 'Montserrat', Helvetica, Arial, sans-serif; font-size: 14px; font-weight: 700; color: #FFFFFF; text-decoration: none; border-radius: 6px; letter-spacing: 0.5px; text-transform: uppercase;">
                      Open Academy Portal &rarr;
                    </a>
                  </td>
                </tr>
              </table>
              <p style="font-size: 12px; line-height: 1.5; color: #777777; margin: 20px 0 0 0;">
                Portal link: <a href="${portalUrl}" target="_blank" style="color: #26AAD1; text-decoration: underline;">${portalUrl}</a>
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding: 24px 36px; background-color: #FFFFFF; border-top: 1px solid #F3F3F3; font-size: 12px; line-height: 1.6; color: #888888;">
              <p style="margin: 0 0 4px 0; font-weight: 600; color: #444444;">Bauhaven Technology &amp; Vocational Center</p>
              <p style="margin: 0;">admissions@bauhaven.com &middot; www.bauhaven.com</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

async function sendApprovalEmail(email: string, name: string): Promise<void> {
  const apiKey = Deno.env.get('RESEND_API_KEY');
  if (!apiKey) return;
  try {
    await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: Deno.env.get('RESEND_APPLICATIONS_FROM') || 'Bauhaven Admissions <team@bauhaven.com>',
        to: [email],
        subject: 'Your Bauhaven application has been approved',
        html: renderApprovalHtml(name),
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
