import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';

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
    return jsonResponse({ error: 'Server misconfiguration: missing Supabase credentials.' }, 500);
  }

  let rawToken: string | undefined;
  try {
    const body = await req.json();
    rawToken = body?.token;
  } catch {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400);
  }

  const token = (rawToken ?? '').trim().toUpperCase();
  if (!token || token.length < 4) {
    return jsonResponse({ error: 'Please enter a valid invitation code.' }, 400);
  }

  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const tokenHash = await sha256Hex(token);

  // 1. Find invitation by token_hash OR plain token
  let { data: invitation, error: invError } = await admin
    .from('invitations')
    .select('*, application:applications(id, applicant_name, full_name, applicant_email, email, tracking_code, offering_id, offerings(title)), enrolment:enrolments(id, cohort_id, cohorts(name), assigned_role)')
    .or(`token_hash.eq.${tokenHash},token.eq.${token}`)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  // 2. Fallback: Check if the token was supplied as an application tracking_code
  if (!invitation) {
    const { data: appMatch } = await admin
      .from('applications')
      .select('id')
      .eq('tracking_code', token)
      .maybeSingle();

    if (appMatch?.id) {
      const { data: invByApp } = await admin
        .from('invitations')
        .select('*, application:applications(id, applicant_name, full_name, applicant_email, email, tracking_code, offering_id, offerings(title)), enrolment:enrolments(id, cohort_id, cohorts(name), assigned_role)')
        .eq('application_id', appMatch.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (invByApp) {
        invitation = invByApp;
      }
    }
  }

  if (invError || !invitation) {
    return jsonResponse({ error: 'Invitation not found or invalid.' }, 404);
  }

  if (invitation.status === 'accepted') {
    return jsonResponse({ error: 'This invitation code has already been redeemed.' }, 409);
  }

  if (invitation.status === 'revoked') {
    return jsonResponse({ error: 'This invitation has been revoked.' }, 409);
  }

  if (invitation.expires_at && new Date(invitation.expires_at) < new Date()) {
    return jsonResponse({ error: 'This invitation has expired.' }, 410);
  }

  const app = invitation.application as any;
  const enrolment = invitation.enrolment as any;
  const applicantName = app?.applicant_name || app?.full_name || '';
  const offeringTitle = app?.offerings?.title || '';
  const cohortName = enrolment?.cohorts?.name || '';

  return jsonResponse({
    id: invitation.id,
    email: invitation.email,
    name: applicantName,
    offeringTitle,
    cohortName,
    status: invitation.status,
    expires_at: invitation.expires_at,
    accepted_at: invitation.accepted_at,
  });
});
