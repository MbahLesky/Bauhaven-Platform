// approve-application
//
// Privileged Bauhaven Admin operation: approves an admissions application,
// creates the enrolment record, issues a secure self-service admission/invitation code,
// and notifies the applicant via email.
//
// Self-Service Onboarding Model:
//   - DOES NOT create a passwordless auth user in auth.users.
//   - Creates a pending_activation enrolment.
//   - Generates an admission code (e.g. BAU-A1B2C3) stored with SHA-256 hash in public.invitations.
//   - Emails the applicant their admission code and direct link to activate their account
//     at https://hub.bauhaven.com/activate?code=BAU-A1B2C3.
//   - The applicant visits the activation page, sets their own chosen password, which creates
//     and activates their account cleanly via activate-participant-account.
//
// Deploy with: supabase functions deploy approve-application --no-verify-jwt
// Required secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, RESEND_API_KEY / RESEND_API_KEY_APPLICATIONS

import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

interface ApprovePayload {
  application_id: string;
  cohort_id?: string | null;
  assigned_role?: string;
  mentor_id?: string | null;
  start_date?: string | null;
  end_date?: string | null;
}

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
    headers: {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    },
  });
}

interface ApprovalEmailDetails {
  name: string;
  offeringTitle?: string;
  cohortName?: string;
  startDate?: string;
  admissionCode?: string;
  activationUrl: string;
  isExistingUser: boolean;
}

function renderApprovalHtml(details: ApprovalEmailDetails): string {
  const safeName = details.name ? details.name : 'there';
  const offeringTitle = details.offeringTitle || 'Bauhaven Programme';
  const cohortName = details.cohortName || 'Active Cohort';
  const startDate = details.startDate || 'Scheduled shortly';
  const { activationUrl, admissionCode, isExistingUser } = details;

  return `<!DOCTYPE html>
<html lang="en" xmlns="http://www.w3.org/1999/xhtml">
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
                    <span style="display: block; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; color: #888888; margin-top: 3px;">Mile IV, Bamenda, Cameroon</span>
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
                We are thrilled to let you know that your application to Bauhaven has been <strong>approved</strong>. You have been officially admitted to the programme.
              </p>

              <!-- Enrolment Summary Card -->
              <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #FBFBFB; border: 1px solid #EBEBEB; border-radius: 6px; margin: 24px 0; border-collapse: separate;">
                <tr>
                  <td style="padding: 18px 20px;">
                    <p style="font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 1px; color: #888888; margin: 0 0 14px 0;">
                      Enrolment Summary
                    </p>
                    <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%">
                      <tr>
                        <td style="padding: 6px 0; font-size: 13px; color: #666666; width: 35%;">Programme:</td>
                        <td style="padding: 6px 0; font-size: 14px; font-weight: 600; color: #1E1E1E;">${offeringTitle}</td>
                      </tr>
                      <tr>
                        <td style="padding: 6px 0; font-size: 13px; color: #666666;">Cohort:</td>
                        <td style="padding: 6px 0; font-size: 14px; font-weight: 600; color: #1E1E1E;">${cohortName}</td>
                      </tr>
                      <tr>
                        <td style="padding: 6px 0; font-size: 13px; color: #666666;">Start Date:</td>
                        <td style="padding: 6px 0; font-size: 14px; font-weight: 600; color: #1E1E1E;">${startDate}</td>
                      </tr>
                      <tr>
                        <td style="padding: 6px 0; font-size: 13px; color: #666666;">Status:</td>
                        <td style="padding: 6px 0; font-size: 13px; font-weight: 700; color: #1B6E44;">Active Enrolment</td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>

              ${
                !isExistingUser && admissionCode
                  ? `
              <!-- Admission Code Card -->
              <div style="background-color: #F0F9FF; border: 1px dashed #0284C7; border-radius: 8px; padding: 20px; text-align: center; margin: 24px 0;">
                <span style="font-size: 11px; font-weight: 700; text-transform: uppercase; letter-spacing: 1.5px; color: #0369A1; display: block; margin-bottom: 8px;">Your Admission Code</span>
                <span style="font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, Courier, monospace; font-size: 26px; font-weight: 800; letter-spacing: 3px; color: #0F172A; display: inline-block; padding: 4px 12px; background: #FFFFFF; border-radius: 6px; border: 1px solid #BAE6FD;">${admissionCode}</span>
                <p style="font-size: 13px; line-height: 1.5; color: #475569; margin: 12px 0 0 0;">
                  Click the button below to set your password and access your Bauhaven Hub account.
                </p>
              </div>
              `
                  : ''
              }

              <table role="presentation" border="0" cellpadding="0" cellspacing="0" style="margin: 28px 0 20px 0;">
                <tr>
                  <td align="center" style="border-radius: 6px; background-color: #D72638;">
                    <a href="${activationUrl}" target="_blank" style="display: inline-block; padding: 14px 34px; font-family: 'Montserrat', Helvetica, Arial, sans-serif; font-size: 14px; font-weight: 700; color: #FFFFFF; text-decoration: none; border-radius: 6px; letter-spacing: 0.5px; text-transform: uppercase;">
                      ${isExistingUser ? 'Open Hub Portal &rarr;' : 'Activate Account & Set Password &rarr;'}
                    </a>
                  </td>
                </tr>
              </table>
              <p style="font-size: 12px; line-height: 1.5; color: #777777; margin: 20px 0 0 0;">
                Direct link: <a href="${activationUrl}" target="_blank" style="color: #26AAD1; text-decoration: underline;">${activationUrl}</a>
              </p>
            </td>
          </tr>
          <tr>
            <td style="padding: 24px 36px; background-color: #FFFFFF; border-top: 1px solid #F3F3F3; font-size: 12px; line-height: 1.6; color: #888888;">
              <p style="margin: 0 0 4px 0; font-weight: 600; color: #444444;">Bauhaven</p>
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

async function sendApprovalEmail(email: string, details: ApprovalEmailDetails): Promise<void> {
  const apiKey = Deno.env.get('RESEND_API_KEY_APPLICATIONS') || Deno.env.get('RESEND_API_KEY');
  if (!apiKey) return;
  const fromEmail = Deno.env.get('RESEND_FROM_APPLICATIONS') || Deno.env.get('RESEND_APPLICATIONS_FROM') || 'Bauhaven Admissions <admissions@bauhaven.com>';
  
  try {
    // 1. Primary delivery: Use official published Resend template 'application-approval'
    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        from: fromEmail,
        to: [email],
        subject: 'Your Bauhaven application has been approved',
        template: {
          id: 'application-approval',
          variables: {
            name: details.name || 'there',
            NAME: details.name || 'there',
            offering_title: details.offeringTitle || 'Bauhaven Programme',
            cohort_name: details.cohortName || 'Active Cohort',
            start_date: details.startDate || 'Scheduled shortly',
            portal_url: details.activationUrl,
            activation_url: details.activationUrl,
            admission_code: details.admissionCode || '',
            activation_code: details.admissionCode || '',
          },
        },
      }),
    });

    if (!res.ok) {
      // 2. Fallback delivery: Standard responsive HTML if template call is rejected
      await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from: fromEmail,
          to: [email],
          subject: 'Your Bauhaven application has been approved',
          html: renderApprovalHtml(details),
        }),
      });
    }
  } catch {
    // Best-effort
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: {
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
      },
    });
  }

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

  // Caller client verification
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

  // Check decision permission
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
  // means it was approved before. Return the existing result.
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

  // Check if applicant already has a registered user profile
  const { data: existingProfile } = await admin
    .from('profiles')
    .select('id')
    .ilike('email', email)
    .maybeSingle();

  const isExistingUser = !!existingProfile;
  const userId = existingProfile?.id ?? null;
  const hubBase = Deno.env.get('HUB_PORTAL_URL') || Deno.env.get('ACADEMY_PORTAL_URL') || 'https://hub.bauhaven.com';

  // 1. Create or upsert the enrolment
  // Notice: profile_id is nullable (migration 0048), so we do NOT need to create a dummy user in auth.users!
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
        status: isExistingUser ? 'active' : 'pending_activation',
      },
      { onConflict: 'application_id' },
    )
    .select('id')
    .single();

  if (enrolmentError) {
    return jsonResponse({ error: `Failed to create enrolment: ${enrolmentError.message}` }, 500);
  }

  // 2. Record the approval decision
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

  // 3. Issue admission code & invitation
  let admissionCode: string | undefined;
  let activationUrl: string;

  if (isExistingUser) {
    // Existing user: mark invitation accepted and point them straight to hub login
    await admin.from('invitations').insert({
      application_id: application.id,
      enrolment_id: enrolment.id,
      email,
      status: 'accepted',
      sent_at: new Date().toISOString(),
      accepted_at: new Date().toISOString(),
    });
    activationUrl = `${hubBase}/login`;
  } else {
    // New applicant: generate clean, human-friendly admission code
    const randomHex = crypto.randomUUID().replace(/[^a-zA-Z0-9]/g, '').substring(0, 6).toUpperCase();
    admissionCode = `BAU-${randomHex}`;
    const tokenHash = await sha256Hex(admissionCode);

    await admin.from('invitations').insert({
      application_id: application.id,
      enrolment_id: enrolment.id,
      email,
      token: admissionCode,
      token_hash: tokenHash,
      status: 'sent',
      sent_at: new Date().toISOString(),
      expires_at: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
    });

    activationUrl = `${hubBase}/activate?code=${admissionCode}`;
  }

  // 4. Update application status
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

  // 5. Send approval notification email
  let offeringTitle: string | undefined;
  if (application.offering_id) {
    const { data: offering } = await admin
      .from('offerings')
      .select('title')
      .eq('id', application.offering_id)
      .maybeSingle();
    offeringTitle = offering?.title;
  }

  let cohortName: string | undefined;
  if (payload.cohort_id) {
    const { data: cohort } = await admin
      .from('cohorts')
      .select('name')
      .eq('id', payload.cohort_id)
      .maybeSingle();
    cohortName = cohort?.name;
  }

  await sendApprovalEmail(email, {
    name: application.applicant_name ?? '',
    offeringTitle,
    cohortName,
    startDate: payload.start_date ?? undefined,
    admissionCode,
    activationUrl,
    isExistingUser,
  });

  // 6. Log audit event
  await admin.rpc('log_audit_event', {
    p_actor_id: callerId,
    p_action: 'application.approved',
    p_entity_type: 'application',
    p_entity_id: application.id,
    p_before: { status: application.status },
    p_after: { status: 'approved', enrolment_id: enrolment.id, user_id: userId },
    p_outcome: 'success',
    p_metadata: { invited: !isExistingUser, admission_code: admissionCode ?? null },
    p_request_id: null,
  });

  return jsonResponse({
    ok: true,
    alreadyApproved: false,
    applicationId: application.id,
    userId,
    enrolmentId: enrolment.id,
    invited: !isExistingUser,
    admissionCode: admissionCode ?? null,
  });
});
