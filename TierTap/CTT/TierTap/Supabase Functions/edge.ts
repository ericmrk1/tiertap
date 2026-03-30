// supabase/functions/gemini-router/index.ts

const corsHeaders = new Headers({
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
});

const LOGGING_MODE = false;

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_PRODUCTION");
const GEMINI_MODEL_NAME = Deno.env.get("GEMINI_MODEL_NAME");
const IOS_APP_NAME = Deno.env.get("IOS_APP_NAME");

if (!GEMINI_API_KEY) {
  console.error("GEMINI_API_KEY is not set in environment variables");
}

// gemini-2.5-flash is current model here.
// gemini-2.5-flash-lite is better....


console.log("gemini-proxy function loaded");

/** Strips `tierTapLanguagePreamble` and prepends it to the first user text part (Gemini multimodal safe). */
function mergeTierTapLanguagePreamble(raw: string): string {
  let body: Record<string, unknown>;
  try {
    body = JSON.parse(raw) as Record<string, unknown>;
  } catch {
    return raw;
  }
  const pre = body["tierTapLanguagePreamble"];
  delete body["tierTapLanguagePreamble"];
  if (typeof pre !== "string" || pre.length === 0) {
    return JSON.stringify(body);
  }
  const contents = body["contents"];
  if (!Array.isArray(contents) || contents.length === 0) {
    return JSON.stringify(body);
  }
  for (const item of contents) {
    if (typeof item !== "object" || item === null) continue;
    const parts = (item as Record<string, unknown>)["parts"];
    if (!Array.isArray(parts)) continue;
    for (const part of parts) {
      if (typeof part !== "object" || part === null) continue;
      const t = (part as Record<string, unknown>)["text"];
      if (typeof t === "string" && t.length > 0) {
        (part as Record<string, unknown>)["text"] = `${pre}\n\n---\n\n${t}`;
        return JSON.stringify(body);
      }
    }
  }
  return JSON.stringify(body);
}

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

    if (LOGGING_MODE)
    {
      console.log("Incoming request body (to forward to Gemini):", raw);
    }

    bodyForGemini = mergeTierTapLanguagePreamble(raw);
  } catch (e) {
    console.error("Error reading incoming body for logging:", e);
    bodyForGemini = req.body;
  }

  if (LOGGING_MODE) {
    console.log( "Throttle.....")
  }

  await new Promise(r => setTimeout(r, 100))

  // Build headers for Gemini
  const headers = new Headers();
  headers.set("content-type", "application/json");
  headers.set("x-goog-api-key", GEMINI_API_KEY);
  headers.set("x-ios-bundle-identifier", IOS_APP_NAME); // keep if using iOS-restricted key

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

  if (LOGGING_MODE)
  {
    console.log("Gemini response status:", geminiStatus, geminiStatusText);
    console.log("Gemini response body:", geminiText);
  }
  
  const responseHeaders = new Headers(geminiResponse.headers);
  corsHeaders.forEach((value, key) => responseHeaders.set(key, value));
  responseHeaders.set("content-type", "application/json");

  return new Response(geminiText, {
    status: geminiStatus,
    statusText: geminiStatusText,
    headers: responseHeaders,
  });
});
