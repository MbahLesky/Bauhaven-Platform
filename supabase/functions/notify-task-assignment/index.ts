// notify-task-assignment
//
// Sends "you've been assigned a task" emails via Resend. Called by
// TasksService.assignToCohort right after the task_assignments upsert
// succeeds (same pattern as every other privileged operation in this repo -
// invite-administrator, approve-application - client calls the Edge
// Function directly; there is no Database Webhook/pg_net infrastructure in
// this project, so this doesn't introduce one just for this).
//
// Non-fatal by design: if this fails (Resend not configured yet, one bad
// email address, etc.) the caller should NOT treat the task assignment
// itself as failed - the assignment already succeeded before this was
// called. Errors are returned in the response body, not thrown as a 500,
// so the client can surface a soft warning without rolling anything back.
//
// Required secret: RESEND_API_KEY (set via `supabase secrets set` or the
// Management API - not present until Resend is configured, see
// BauhavenDocs/EMAIL_NOTIFICATIONS_SETUP.md).
//
// Deploy with: supabase functions deploy notify-task-assignment

// npm:, not jsr: - see invite-administrator's identical comment for why.
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

interface NotifyPayload {
  task_id: string;
  enrolment_ids: string[];
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

function renderTaskAssignmentHtml(name: string, taskTitle: string, dueLabel: string, instructions?: string | null): string {
  const portalUrl = Deno.env.get('ACADEMY_PORTAL_URL') || 'https://academy.bauhaven.com';
  const instructionsPreview = instructions?.trim() || 'Review the assignment description and resources directly in your Academy portal.';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>New Task Assigned - Bauhaven Academy</title>
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
                    <span style="display: block; font-size: 11px; font-weight: 600; text-transform: uppercase; letter-spacing: 1px; color: #888888; margin-top: 3px;">Academy Portal</span>
                  </td>
                  <td align="right" valign="middle">
                    <span style="display: inline-block; padding: 4px 10px; background-color: #E8F6FA; color: #026E86; font-size: 11px; font-weight: 700; border-radius: 4px; text-transform: uppercase; letter-spacing: 0.5px; border: 1px solid #C4EBF3;">Task Assigned</span>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="padding: 36px 36px 28px 36px;">
              <h1 style="font-family: 'Montserrat', Helvetica, Arial, sans-serif; font-size: 22px; font-weight: 800; color: #1E1E1E; margin: 0 0 16px 0; line-height: 1.3;">
                New Task Assigned
              </h1>
              <p style="font-size: 15px; line-height: 1.6; color: #3E3E3E; margin: 0 0 20px 0;">
                Hello ${name}, you have been assigned a new task on Bauhaven:
              </p>
              <table role="presentation" border="0" cellpadding="0" cellspacing="0" width="100%" style="background-color: #FBFBFB; border: 1px solid #EBEBEB; border-radius: 6px; margin: 20px 0 24px 0; border-collapse: separate;">
                <tr>
                  <td style="padding: 20px 22px;">
                    <div style="font-family: 'Montserrat', Helvetica, Arial, sans-serif; font-size: 17px; font-weight: 700; color: #1E1E1E; margin-bottom: 12px;">
                      ${taskTitle}
                    </div>
                    <div style="font-size: 13px; color: #666666; margin-bottom: 8px;">
                      <strong>Deadline:</strong> <span style="color: #D72638; font-weight: 700;">${dueLabel}</span>
                    </div>
                    <div style="font-size: 13px; line-height: 1.5; color: #4E4E4E; border-top: 1px dashed #E5E5E5; padding-top: 10px; margin-top: 10px; font-style: italic;">
                      ${instructionsPreview}
                    </div>
                  </td>
                </tr>
              </table>
              <table role="presentation" border="0" cellpadding="0" cellspacing="0" style="margin: 28px 0 20px 0;">
                <tr>
                  <td align="center" style="border-radius: 6px; background-color: #D72638;">
                    <a href="${portalUrl}" target="_blank" style="display: inline-block; padding: 14px 34px; font-family: 'Montserrat', Helvetica, Arial, sans-serif; font-size: 14px; font-weight: 700; color: #FFFFFF; text-decoration: none; border-radius: 6px; letter-spacing: 0.5px; text-transform: uppercase;">
                      View Task &amp; Submit &rarr;
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
              <p style="margin: 0;">info@bauhaven.com &middot; www.bauhaven.com</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

async function sendEmail(apiKey: string, to: string, subject: string, html: string): Promise<void> {
  const from = Deno.env.get('RESEND_TASKS_FROM') || 'Bauhaven Tasks <info@bauhaven.com>';
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from,
      to: [to],
      subject,
      html,
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => '');
    throw new Error(`Resend API error ${res.status}: ${body}`);
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') {
    return jsonResponse({ error: 'Method not allowed' }, 405);
  }

  const supabaseUrl = Deno.env.get('SUPABASE_URL');
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  const resendApiKey = Deno.env.get('RESEND_API_KEY');
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: 'Server misconfiguration: missing Supabase service credentials.' }, 500);
  }

  const authHeader = req.headers.get('Authorization');
  if (!authHeader) {
    return jsonResponse({ error: 'Missing Authorization header.' }, 401);
  }

  // Just confirms the caller is a real signed-in user - the actual
  // authorization for *assigning* the task already happened client-side
  // against RLS before this was ever called; this function only sends
  // mail, it doesn't decide who's allowed to assign anything.
  const callerClient: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    global: { headers: { Authorization: authHeader } },
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: userData, error: userError } = await callerClient.auth.getUser();
  if (userError || !userData?.user) {
    return jsonResponse({ error: 'Invalid or expired session.' }, 401);
  }

  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  let payload: NotifyPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400);
  }
  if (!payload.task_id || !Array.isArray(payload.enrolment_ids) || payload.enrolment_ids.length === 0) {
    return jsonResponse({ error: 'task_id and a non-empty enrolment_ids array are required.' }, 400);
  }

  const { data: task, error: taskError } = await admin
    .from('tasks')
    .select('title, due_at, instructions')
    .eq('id', payload.task_id)
    .maybeSingle();
  if (taskError || !task) {
    return jsonResponse({ error: `Task not found: ${taskError?.message ?? payload.task_id}` }, 404);
  }

  const { data: enrolments, error: enrolmentsError } = await admin
    .from('enrolments')
    .select('id, profiles(full_name, email)')
    .in('id', payload.enrolment_ids);
  if (enrolmentsError) {
    return jsonResponse({ error: `Failed to load assignees: ${enrolmentsError.message}` }, 500);
  }

  if (!resendApiKey) {
    // Genuinely not configured yet - not an error in the assignment flow,
    // just nothing to send. Tell the caller plainly rather than pretending
    // it worked.
    return jsonResponse({
      ok: true,
      sent: 0,
      skipped: enrolments.length,
      reason: 'RESEND_API_KEY is not configured - emails were not sent.',
    });
  }

  const dueLabel = task.due_at
    ? new Date(task.due_at).toLocaleDateString('en-GB', { day: 'numeric', month: 'long', year: 'numeric' })
    : 'no fixed deadline';

  let sent = 0;
  const failures: string[] = [];
  for (const row of enrolments) {
    const profile = row.profiles as { full_name?: string; email?: string } | null;
    const email = profile?.email;
    if (!email) continue;
    const name = profile?.full_name?.trim() || 'there';
    try {
      await sendEmail(
        resendApiKey,
        email,
        `New task assigned: ${task.title}`,
        renderTaskAssignmentHtml(name, task.title, dueLabel, task.instructions),
      );
      sent += 1;
    } catch (error) {
      failures.push(`${email}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  return jsonResponse({ ok: true, sent, failed: failures.length, failures });
});
