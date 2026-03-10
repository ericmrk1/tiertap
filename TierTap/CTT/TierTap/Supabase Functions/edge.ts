// supabase/functions/gemini-router/index.ts

const corsHeaders = new Headers({
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
});

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_PRODUCTION");
const GEMINI_MODEL_NAME = Deno.env.get("GEMINI_MODEL_NAME");

if (!GEMINI_API_KEY) {
  console.error("GEMINI_API_KEY is not set in environment variables");
}

console.log("gemini-proxy function loaded");

Deno.serve(async (req: Request) => {
  console.log("Incoming request:", {
    method: req.method,
    url: req.url,
    headers: Object.fromEntries(req.headers),
  });

  // Authorizatino Check
  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response("Unauthorized", { status: 401 });
  }


  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    console.log("OPTIONS preflight handled");
    return new Response(null, { headers: corsHeaders });
  }

  if (!GEMINI_API_KEY) {
    console.error("GEMINI_API_KEY missing, returning 500 before calling Gemini");
    return new Response("GEMINI_API_KEY not configured on server", {
      status: 500,
      headers: corsHeaders,
    });
  }

  const url = new URL(req.url);
  const model = url.searchParams.get("model") ?? GEMINI_MODEL_NAME;
  const geminiUrl =
    `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`;

  console.log("Calling Gemini URL:", geminiUrl);

  // Read and log body (clone so we can still forward)
  let bodyForGemini: BodyInit | null = null;
  try {
    const raw = await req.clone().text();
    console.log("Incoming request body (to forward to Gemini):", raw);
    bodyForGemini = raw;
  } catch (e) {
    console.error("Error reading incoming body for logging:", e);
    bodyForGemini = req.body;
  }

  // Build headers for Gemini
  const headers = new Headers();
  headers.set("content-type", "application/json");
  headers.set("x-goog-api-key", GEMINI_API_KEY);
  headers.set("x-ios-bundle-identifier", "com.app.runkicks"); // keep if using iOS-restricted key

  console.log("Outgoing Gemini headers:", Object.fromEntries(headers));

  let geminiResponse: Response;
  try {
    geminiResponse = await fetch(geminiUrl, {
      method: "POST",
      headers,
      body: bodyForGemini,
    });
  } catch (e) {
    console.error("Network error calling Gemini:", e);
    return new Response("Error calling Gemini", {
      status: 502,
      headers: corsHeaders,
    });
  }

  const geminiStatus = geminiResponse.status;
  const geminiStatusText = geminiResponse.statusText;
  const geminiText = await geminiResponse.text();

  console.log("Gemini response status:", geminiStatus, geminiStatusText);
  console.log("Gemini response body:", geminiText);

  const responseHeaders = new Headers(geminiResponse.headers);
  corsHeaders.forEach((value, key) => responseHeaders.set(key, value));
  responseHeaders.set("content-type", "application/json");

  return new Response(geminiText, {
    status: geminiStatus,
    statusText: geminiStatusText,
    headers: responseHeaders,
  });
});
