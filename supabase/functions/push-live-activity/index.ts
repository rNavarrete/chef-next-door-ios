// Sends push to APNs: Live Activity card updates, and ordinary alerts.
//
// Two shapes through one door, because they share the only hard part — APNs
// authenticates with an ES256-signed JWT and `pgcrypto` cannot sign ECDSA. They
// share nothing else: an alert needs a different topic, a different push-type
// header, and goes to a device token rather than a per-activity one. A request
// with `kind: "alert"` takes the second path.
//
// Deliberately thin. Everything about *what* to say is decided in
// `activity_payload_for_thread()` and `message_alert_payload()` (migrations 045
// and 047), next to the data; this signs a request and posts it. The only reason it exists at all is that APNs
// authenticates with an ES256-signed JWT and `pgcrypto` cannot sign ECDSA — so
// pg_net, which fetches the permit register perfectly well on its own, cannot
// talk to Apple.
//
// Secrets (set with `supabase secrets set`):
//   APNS_KEY_ID       the 10-character Key ID from the developer portal
//   APNS_TEAM_ID      HCEA5N57HT
//   APNS_PRIVATE_KEY  the .p8 contents, including the BEGIN/END lines
//   LK_PUSH_SECRET    shared with app_secrets.push_fn_secret
//
// Deploy with `--no-verify-jwt`: the caller is a Postgres trigger, authorised
// by the shared secret above rather than a user JWT. That secret only permits
// "push to this thread", which is a far smaller capability than the
// service-role key would be.

const APNS_HOSTS = {
  development: "https://api.sandbox.push.apple.com",
  production: "https://api.push.apple.com",
} as const;

const BUNDLE_ID = "com.litkitchen.app";

interface AlertRequest {
  kind: "alert";
  tokens: { token: string; environment: keyof typeof APNS_HOSTS }[];
  title: string;
  body: string;
  thread_id: string;
  badge?: number;
}

interface PushRequest {
  token: string;
  environment: keyof typeof APNS_HOSTS;
  claimId: string;
  event: "update" | "end";
  contentState: Record<string, unknown>;
}

// ---------------------------------------------------------------------------
// APNs auth token
//
// Apple rate-limits token *generation* and rejects tokens older than an hour,
// so this is cached across invocations of a warm instance and rebuilt at 50
// minutes. Signing on every push is the documented way to get throttled.
// ---------------------------------------------------------------------------
let cachedJWT: { token: string; madeAt: number } | null = null;

async function apnsAuthToken(): Promise<string> {
  const now = Date.now();
  if (cachedJWT && now - cachedJWT.madeAt < 50 * 60 * 1000) return cachedJWT.token;

  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const pem = Deno.env.get("APNS_PRIVATE_KEY");
  if (!keyId || !teamId || !pem) throw new Error("APNs credentials are not configured");

  const der = pemToArrayBuffer(pem);
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  );

  const header = { alg: "ES256", kid: keyId };
  const claims = { iss: teamId, iat: Math.floor(now / 1000) };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claims))}`;

  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(unsigned),
  );

  const token = `${unsigned}.${b64urlBytes(new Uint8Array(signature))}`;
  cachedJWT = { token, madeAt: now };
  return token;
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const raw = atob(body);
  const bytes = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) bytes[i] = raw.charCodeAt(i);
  return bytes.buffer;
}

const b64url = (s: string) => b64urlBytes(new TextEncoder().encode(s));
const b64urlBytes = (bytes: Uint8Array) =>
  btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

// ---------------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("method not allowed", { status: 405 });

  const expected = Deno.env.get("LK_PUSH_SECRET");
  if (!expected || req.headers.get("x-lk-secret") !== expected) {
    return new Response("unauthorized", { status: 401 });
  }

  let body: PushRequest;
  try {
    body = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }
  // ── ordinary alert ──────────────────────────────────────────────────────
  // Fans out to every device the recipient has registered. One failure must
  // not stop the others: a stale token on an old handset would otherwise mute
  // the phone in their pocket.
  if (body?.kind === "alert") {
    const alert = body as unknown as AlertRequest;
    if (!alert.tokens?.length) return new Response("no tokens", { status: 400 });

    const jwt = await apnsAuthToken();
    const results = await Promise.all(alert.tokens.map(async (t) => {
      const host = APNS_HOSTS[t.environment] ?? APNS_HOSTS.development;
      const res = await fetch(`${host}/3/device/${t.token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          // No `.push-type.liveactivity` suffix here, and push-type "alert".
          // Reusing the Live Activity topic silently delivers nothing.
          "apns-topic": BUNDLE_ID,
          "apns-push-type": "alert",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          aps: {
            alert: { title: alert.title, body: alert.body },
            sound: "default",
            badge: alert.badge ?? 0,
            "thread-id": alert.thread_id,
          },
          thread_id: alert.thread_id,
        }),
      });
      const text = await res.text();

      // A token Apple has retired will never work again. Leaving it means
      // pushing into the void on every future message.
      if (res.status === 410 || text.includes("BadDeviceToken")) {
        const url = Deno.env.get("SUPABASE_URL");
        const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
        if (url && key) {
          await fetch(
            `${url}/rest/v1/device_tokens?token=eq.${encodeURIComponent(t.token)}`,
            { method: "DELETE", headers: { apikey: key, authorization: `Bearer ${key}` } },
          );
        }
      }
      return { token: t.token.slice(-8), status: res.status, body: text };
    }));

    return new Response(JSON.stringify({ sent: results }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  }

  if (!body?.token || !body?.contentState) {
    return new Response("missing token or contentState", { status: 400 });
  }

  const host = APNS_HOSTS[body.environment] ?? APNS_HOSTS.development;
  const jwt = await apnsAuthToken();

  // `timestamp` is required and must be seconds. `event: "end"` retires the
  // card; "update" changes it in place.
  const payload = {
    aps: {
      timestamp: Math.floor(Date.now() / 1000),
      event: body.event ?? "update",
      "content-state": body.contentState,
      ...(body.event === "end" ? { "dismissal-date": Math.floor(Date.now() / 1000) } : {}),
    },
  };

  const res = await fetch(`${host}/3/device/${body.token}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      // Both of these are mandatory and neither fails loudly if wrong: Apple
      // accepts the request and the card simply never changes. The topic
      // suffix in particular is easy to omit.
      "apns-topic": `${BUNDLE_ID}.push-type.liveactivity`,
      "apns-push-type": "liveactivity",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(payload),
  });

  const text = await res.text();

  // 410 Gone / 400 BadDeviceToken mean the activity is over or the token is
  // stale. Dropping the row stops us pushing into the void forever.
  if (res.status === 410 || text.includes("BadDeviceToken")) {
    const url = Deno.env.get("SUPABASE_URL");
    const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (url && key) {
      // `conversation_id`, not `claim_id`. 045 re-keyed these tokens onto
      // conversations and left this delete pointing at a column that is now
      // null for every row it writes — so a dead token would never have been
      // cleaned up, and every later push would keep hitting a 410.
      await fetch(`${url}/rest/v1/live_activity_tokens?conversation_id=eq.${body.threadId}`, {
        method: "DELETE",
        headers: { apikey: key, authorization: `Bearer ${key}` },
      });
    }
  }

  return new Response(
    JSON.stringify({ apnsStatus: res.status, apnsBody: text, apnsId: res.headers.get("apns-id") }),
    { status: res.ok ? 200 : 502, headers: { "content-type": "application/json" } },
  );
});
