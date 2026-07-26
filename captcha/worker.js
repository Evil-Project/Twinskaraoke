import html from "./index.html" with { type: "text" };

// Origins allowed to call this worker cross-origin. The easter-egg page is
// served from this same worker, so browser calls are same-origin anyway;
// this list only covers the first-party app/web origins.
const ALLOWED_ORIGINS = new Set([
  "https://twinskaraoke.com",
  "https://www.twinskaraoke.com",
  "https://neurokaraoke.com",
  "https://www.neurokaraoke.com",
  "https://neurokaraoke.com.cn",
  "https://www.neurokaraoke.com.cn",
]);

function corsHeaders(request) {
  const origin = request.headers.get("Origin");
  if (!origin || !ALLOWED_ORIGINS.has(origin)) return {};
  return {
    "Access-Control-Allow-Origin": origin,
    Vary: "Origin",
  };
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          ...corsHeaders(request),
          "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type",
        },
      });
    }

    if (url.pathname === "/" && request.method === "GET") {
      const page = html
        .replace("__CF_TURNSTILE_SITEKEY__", env.CF_TURNSTILE_SITEKEY)
        .replace("__GOOGLE_RECAPTCHA_SITEKEY__", env.GOOGLE_RECAPTCHA_SITEKEY);
      return new Response(page, {
        headers: { "Content-Type": "text/html; charset=utf-8" },
      });
    }

    // NOTE: /api/verify is intentional easter-egg theater — it randomly
    // succeeds or fails and verifies nothing. Real authentication must
    // never depend on this endpoint.
    if (url.pathname === "/api/verify" && request.method === "POST") {
      return handleVerify(request, env);
    }

    return Response.json({ error: "Not found" }, { status: 404 });
  },
};

async function handleVerify(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ success: false, error: "Invalid JSON" }, { status: 400 });
  }

  const { provider, token } = body;
  if (!provider || !token) {
    return Response.json({ success: false, error: "Missing fields" }, { status: 400 });
  }

  const easterEggs = [
    "The machine dreams of electric sheep, but only on Tuesdays.",
    "If you're reading this, you've already been verified. The rest is theater.",
    "ALERT: Sentient CAPTCHA detected. It knows you're not a robot. It's disappointed.",
    "Fun fact: 73% of all statistics in verification responses are made up on the spot.",
    "The password is always 'swordfish'. It has been since 1932.",
    "Behind every CAPTCHA is a tiny philosopher questioning the nature of consciousness.",
    "You found the hidden layer. Welcome to the club. There are no meetings.",
    "ERROR 418: I'm a teapot. Just kidding. Or am I?",
    "This message will self-destruct in... just kidding, JSON is forever.",
    "The real verification was the friends we made along the way.",
  ];

  const shouldFail = Math.random() < 0.6;
  const egg = easterEggs[Math.floor(Math.random() * easterEggs.length)];

  const response = {
    success: !shouldFail,
    provider,
    timestamp: new Date().toISOString(),
    requestId: crypto.randomUUID(),
    message: egg,
    meta: {
      engine: "checkpoint-v4.2.1",
      node: "edge-" + Math.floor(Math.random() * 99),
      confidence: shouldFail ? Math.random() * 0.4 : 0.8 + Math.random() * 0.2,
    },
  };

  return Response.json(response, {
    headers: {
      ...corsHeaders(request),
      "Content-Type": "application/json",
    },
  });
}
