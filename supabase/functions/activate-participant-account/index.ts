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

  let body: any;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: 'Invalid JSON body.' }, 400);
  }

  const token = (body?.token ?? '').trim().toUpperCase();
  const password = (body?.password ?? '').toString();

  if (!token) {
    return jsonResponse({ error: 'Admission code is required.' }, 400);
  }
  if (!password || password.length < 8) {
    return jsonResponse({ error: 'Password must be at least 8 characters.' }, 400);
  }

  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const tokenHash = await sha256Hex(token);

  // 1. Look up invitation
  let { data: invitation, error: invError } = await admin
    .from('invitations')
    .select('*, application:applications(id, applicant_name, full_name, applicant_email, email, applicant_phone, phone, tracking_code, offering_id), enrolment:enrolments(id, cohort_id, assigned_role)')
    .or(`token_hash.eq.${tokenHash},token.eq.${token}`)
    .order('created_at', { ascending: false })
    .limit(1)
    .maybeSingle();

  // Fallback: check tracking_code
  if (!invitation) {
    const { data: appMatch } = await admin
      .from('applications')
      .select('id')
      .eq('tracking_code', token)
      .maybeSingle();

    if (appMatch?.id) {
      const { data: invByApp } = await admin
        .from('invitations')
        .select('*, application:applications(id, applicant_name, full_name, applicant_email, email, applicant_phone, phone, tracking_code, offering_id), enrolment:enrolments(id, cohort_id, assigned_role)')
        .eq('application_id', appMatch.id)
        .order('created_at', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (invByApp) invitation = invByApp;
    }
  }

  if (invError || !invitation) {
    return jsonResponse({ error: 'Invitation not found or invalid.' }, 404);
  }

  if (invitation.status === 'accepted') {
    return jsonResponse({ error: 'This invitation code has already been redeemed. Please sign in.' }, 409);
  }
  if (invitation.status === 'revoked') {
    return jsonResponse({ error: 'This invitation has been revoked.' }, 409);
  }
  if (invitation.expires_at && new Date(invitation.expires_at) < new Date()) {
    return jsonResponse({ error: 'This invitation has expired. Contact admissions for a new code.' }, 410);
  }

  const email = (invitation.email ?? '').trim().toLowerCase();
  if (!email) {
    return jsonResponse({ error: 'Invitation has no valid email address.' }, 422);
  }

  const app = invitation.application as any;
  const applicantName = (app?.applicant_name || app?.full_name || email.split('@')[0]).trim();
  const phone = app?.applicant_phone || app?.phone || null;

  // 2. Auth user management: Find existing user or create brand new user
  let userId: string;
  const { data: existingUsers } = await admin.auth.admin.listUsers();
  const existingUser = existingUsers?.users?.find((u) => u.email?.toLowerCase() === email);

  if (existingUser) {
    userId = existingUser.id;
    // Set the password user explicitly chose and confirm their email
    const { error: updateAuthErr } = await admin.auth.admin.updateUserById(userId, {
      password,
      email_confirm: true,
      user_metadata: { full_name: applicantName },
    });
    if (updateAuthErr) {
      return jsonResponse({ error: `Could not update account credentials: ${updateAuthErr.message}` }, 500);
    }
  } else {
    // Create new account with chosen password
    const { data: newUser, error: createAuthErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { full_name: applicantName },
    });
    if (createAuthErr || !newUser?.user) {
      return jsonResponse({ error: `Could not create account: ${createAuthErr?.message}` }, 500);
    }
    userId = newUser.user.id;
  }

  // 3. Ensure profiles record exists and is active
  await admin.from('profiles').upsert(
    {
      id: userId,
      email,
      full_name: applicantName,
      phone,
      status: 'active',
      profile_completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: 'id' }
  );

  // 4. Activate or create enrolment
  let enrolmentId = invitation.enrolment_id;
  if (enrolmentId) {
    await admin
      .from('enrolments')
      .update({
        profile_id: userId,
        status: 'active',
        activated_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      })
      .eq('id', enrolmentId);
  } else {
    const { data: newEnrolment } = await admin
      .from('enrolments')
      .upsert(
        {
          profile_id: userId,
          application_id: app?.id ?? null,
          offering_id: app?.offering_id ?? null,
          cohort_id: invitation.enrolment?.cohort_id ?? null,
          assigned_role: invitation.enrolment?.assigned_role ?? 'Intern',
          status: 'active',
          activated_at: new Date().toISOString(),
        },
        { onConflict: 'application_id' }
      )
      .select('id')
      .single();
    if (newEnrolment?.id) {
      enrolmentId = newEnrolment.id;
    }
  }

  // 5. Grant learner/participant role
  const { data: learnerRole } = await admin
    .from('roles')
    .select('id')
    .eq('code', 'learner')
    .maybeSingle();

  if (learnerRole?.id) {
    const { data: existingRole } = await admin
      .from('user_role_assignments')
      .select('id')
      .eq('user_id', userId)
      .eq('role_id', learnerRole.id)
      .maybeSingle();

    if (!existingRole) {
      await admin.from('user_role_assignments').insert({
        user_id: userId,
        role_id: learnerRole.id,
        scope_type: 'organisation',
        assignment_type: 'permanent',
        status: 'active',
      });
    }
  }

  // 6. Mark invitation accepted
  await admin
    .from('invitations')
    .update({
      enrolment_id: enrolmentId,
      status: 'accepted',
      accepted_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq('id', invitation.id);

  return jsonResponse({
    ok: true,
    email,
    userId,
    enrolmentId,
  });
});

