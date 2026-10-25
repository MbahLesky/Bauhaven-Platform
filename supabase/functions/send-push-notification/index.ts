// send-push-notification
//
// Supabase Edge Function to dispatch Firebase Cloud Messaging (FCM) push
// notifications to web and mobile clients using the FCM HTTP v1 API.
//
// Supports:
// 1. Direct recipient delivery via profile IDs (queries fcm_device_tokens)
// 2. Broadcast / topic delivery (e.g. "announcements", "cohort_<id>")
// 3. Stale token cleanup (automatically deletes invalid or unregistered tokens)
// 4. In-app notifications table logging (public.notifications)
//
// Required Secrets:
// - FIREBASE_SERVICE_ACCOUNT: Full JSON string of Google Firebase Service Account
//   OR individual secrets:
//   FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY
// - SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY (injected automatically)

import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2";

interface PushPayload {
  recipient_ids?: string[];
  topic?: string;
  title: string;
  body: string;
  icon?: string;
  badge?: string;
  url?: string;
  data?: Record<string, string>;
  type?: string;
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN[ A-Z_-]+-----/, "")
    .replace(/-----END[ A-Z_-]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

async function getGoogleAccessToken(clientEmail: string, privateKeyPem: string): Promise<string> {
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 3600;
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: clientEmail,
    sub: clientEmail,
    aud: "https://oauth2.googleapis.com/token",
    iat,
    exp,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const b64Url = (obj: unknown) =>
    btoa(JSON.stringify(obj))
      .replace(/=/g, "")
      .replace(/\+/g, "-")
      .replace(/\//g, "_");

  const unsignedToken = `${b64Url(header)}.${b64Url(claims)}`;

  const keyBuffer = pemToArrayBuffer(privateKeyPem);
  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBuffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    new TextEncoder().encode(unsignedToken)
  );

  const b64Signature = btoa(String.fromCharCode(...new Uint8Array(signature)))
    .replace(/=/g, "")
    .replace(/\+/g, "-")
    .replace(/\//g, "_");

  const jwt = `${unsignedToken}.${b64Signature}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const data = await res.json();
  if (!res.ok) {
    throw new Error(`Google token exchange failed: ${JSON.stringify(data)}`);
  }
  return data.access_token;
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return jsonResponse({ error: "Server misconfiguration: missing Supabase credentials." }, 500);
  }

  // Load Firebase Service Account
  let projectId = Deno.env.get("FIREBASE_PROJECT_ID");
  let clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL");
  let privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY");

  const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (serviceAccountJson) {
    try {
      const parsed = JSON.parse(serviceAccountJson);
      projectId = parsed.project_id || projectId;
      clientEmail = parsed.client_email || clientEmail;
      privateKey = parsed.private_key || privateKey;
    } catch {
      console.warn("Could not parse FIREBASE_SERVICE_ACCOUNT JSON");
    }
  }

  let payload: PushPayload;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON payload." }, 400);
  }

  if (!payload.title || !payload.body) {
    return jsonResponse({ error: "Title and body are required." }, 400);
  }

  const admin: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Check if Firebase is configured
  if (!projectId || !clientEmail || !privateKey) {
    // If not configured yet, record in-app notification and return soft warning
    console.warn("FCM credentials not configured. Skipping push delivery.");
    if (payload.recipient_ids && payload.recipient_ids.length > 0) {
      const inAppNotifications = payload.recipient_ids.map((uid) => ({
        recipient_id: uid,
        type: payload.type || "system",
        title: payload.title,
        body: payload.body,
        channel: "in_app",
        status: "delivered",
      }));
      await admin.from("notifications").insert(inAppNotifications);
    }
    return jsonResponse({
      ok: true,
      delivered_count: 0,
      warning: "FCM credentials not set in secrets. In-app notifications logged.",
    });
  }

  // Format private key (replace literal \n with real newlines)
  const normalizedKey = privateKey.replace(/\\n/g, "\n");

  let accessToken: string;
  try {
    accessToken = await getGoogleAccessToken(clientEmail, normalizedKey);
  } catch (err) {
    console.error("Failed to obtain Google access token:", err);
    return jsonResponse({ error: `Authentication with Google FCM failed: ${err.message}` }, 502);
  }

  const defaultIcon = payload.icon || "https://bauhaven.com/icon-192.png";
  const defaultBadge = payload.badge || "https://bauhaven.com/icon-192.png";
  const clickActionUrl = payload.url || "https://hub.bauhaven.com";

  let successCount = 0;
  let failureCount = 0;
  const tokensToDelete: string[] = [];

  // Helper to send one FCM message via HTTP v1
  async function sendFcmMessage(message: Record<string, unknown>): Promise<boolean> {
    try {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ message }),
        }
      );

      if (res.ok) {
        return true;
      }

      const errData = await res.json();
      console.warn("FCM delivery failure:", errData);
      const errorCode = errData?.error?.details?.[0]?.errorCode || errData?.error?.status;
      if (errorCode === "UNREGISTERED" || errorCode === "INVALID_ARGUMENT") {
        if (typeof message.token === "string") {
          tokensToDelete.push(message.token);
        }
      }
      return false;
    } catch (e) {
      console.error("FCM dispatch error:", e);
      return false;
    }
  }

  // 1. Topic delivery
  if (payload.topic) {
    const message = {
      topic: payload.topic,
      notification: {
        title: payload.title,
        body: payload.body,
      },
      webpush: {
        notification: {
          icon: defaultIcon,
          badge: defaultBadge,
        },
        fcm_options: {
          link: clickActionUrl,
        },
      },
      data: payload.data || {},
    };

    const sent = await sendFcmMessage(message);
    if (sent) successCount++;
    else failureCount++;
  }

  // 2. Direct recipient delivery
  if (payload.recipient_ids && payload.recipient_ids.length > 0) {
    const { data: tokens, error: tokensError } = await admin
      .from("fcm_device_tokens")
      .select("token, profile_id, platform")
      .in("profile_id", payload.recipient_ids);

    if (!tokensError && tokens && tokens.length > 0) {
      for (const t of tokens) {
        const message = {
          token: t.token,
          notification: {
            title: payload.title,
            body: payload.body,
          },
          webpush: {
            notification: {
              icon: defaultIcon,
              badge: defaultBadge,
            },
            fcm_options: {
              link: clickActionUrl,
            },
          },
          data: {
            ...payload.data,
            url: clickActionUrl,
          },
        };

        const sent = await sendFcmMessage(message);
        if (sent) successCount++;
        else failureCount++;
      }
    }

    // Log to public.notifications table
    const notificationsRows = payload.recipient_ids.map((uid) => ({
      recipient_id: uid,
      type: payload.type || "system",
      title: payload.title,
      body: payload.body,
      channel: "push",
      status: successCount > 0 ? "delivered" : "queued",
      sent_at: new Date().toISOString(),
    }));
    await admin.from("notifications").insert(notificationsRows);
  }

  // Clean up stale tokens
  if (tokensToDelete.length > 0) {
    await admin.from("fcm_device_tokens").delete().in("token", tokensToDelete);
  }

  return jsonResponse({
    ok: true,
    success_count: successCount,
    failure_count: failureCount,
    cleaned_tokens_count: tokensToDelete.length,
  });
});

