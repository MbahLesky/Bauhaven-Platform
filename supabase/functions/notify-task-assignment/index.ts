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

async function sendEmail(apiKey: string, to: string, subject: string, html: string): Promise<void> {
  const res = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${apiKey}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      from: 'Bauhaven <info@bauhaven.com>',
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
        `<p>Hi ${name},</p>
         <p>You've been assigned a new task on Bauhaven: <strong>${task.title}</strong>.</p>
         <p>Due: ${dueLabel}.</p>
         <p>Log in to the Bauhaven Hub to see the full instructions and submit your work.</p>
         <p>ÔÇö Bauhaven</p>`,
      );
      sent += 1;
    } catch (error) {
      failures.push(`${email}: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  return jsonResponse({ ok: true, sent, failed: failures.length, failures });
});
