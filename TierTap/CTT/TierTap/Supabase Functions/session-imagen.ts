const corsHeaders = new Headers({
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
});

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_PRODUCTION");
const IMAGEN_MODEL = Deno.env.get("IMAGEN_MODEL_NAME") ?? "imagen-4.0-generate-001";
const IMAGEN_FALLBACK_MODEL =
  Deno.env.get("IMAGEN_FALLBACK_MODEL_NAME") ?? "imagen-4.0-fast-generate-001";

type ImagenRequest = {
  prompt: string;
  sessionId?: string;
  metricKeys?: string[];
  imageEmphasis?: string;
  playerTraits?: string[];
};

function unauthorized(): Response {
  return new Response("Unauthorized", { status: 401, headers: corsHeaders });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const authHeader = req.headers.get("authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return unauthorized();
  }

  if (!GEMINI_API_KEY) {
    return new Response("GEMINI_API_PRODUCTION is not configured", {
      status: 500,
      headers: corsHeaders,
    });
  }

  let parsed: ImagenRequest;
  try {
    parsed = (await req.json()) as ImagenRequest;
  } catch {
    return new Response("Invalid JSON body", { status: 400, headers: corsHeaders });
  }

  const prompt = (parsed.prompt ?? "").trim();
  if (!prompt) {
    return new Response("Missing prompt", { status: 400, headers: corsHeaders });
  }
  console.log("[session-imagen] incoming request", {
    sessionId: parsed.sessionId ?? null,
    metricKeys: parsed.metricKeys ?? [],
    imageEmphasis: parsed.imageEmphasis ?? null,
    playerTraits: parsed.playerTraits ?? [],
    promptLength: prompt.length,
    prompt,
  });

  const imagenBody = {
    instances: [{ prompt }],
    parameters: {
      sampleCount: 1,
      personGeneration: "allow_adult",
      aspectRatio: "9:16",
    },
  };
  async function callImagen(model: string): Promise<{ upstreamText: string; status: number }> {
    const imagenURL = `https://generativelanguage.googleapis.com/v1beta/models/${model}:predict`;
    console.log("[session-imagen] imagen request", {
      url: imagenURL,
      model,
      hasApiKey: Boolean(GEMINI_API_KEY),
      apiKeyPrefix: GEMINI_API_KEY ? `${GEMINI_API_KEY.slice(0, 6)}...` : null,
      body: imagenBody,
    });
    let upstream: Response;
    try {
      upstream = await fetch(imagenURL, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-goog-api-key": GEMINI_API_KEY,
        },
        body: JSON.stringify(imagenBody),
      });
    } catch (error) {
      console.error("[session-imagen] upstream network error", { model, error });
      throw new Error("NETWORK_ERROR");
    }
    const upstreamText = await upstream.text();
    console.log("[session-imagen] upstream response", {
      model,
      status: upstream.status,
      statusText: upstream.statusText,
      headers: Object.fromEntries(upstream.headers.entries()),
      bodyPreview: upstreamText.slice(0, 4000),
    });
    return { upstreamText, status: upstream.status };
  }

  const modelsToTry = Array.from(new Set([IMAGEN_MODEL, IMAGEN_FALLBACK_MODEL]));
  let upstreamText = "";
  let upstreamStatus = 500;
  let success = false;
  for (const model of modelsToTry) {
    const result = await callImagen(model).catch(() => null);
    if (result === null) {
      upstreamText = "Network error calling Imagen";
      upstreamStatus = 502;
      continue;
    }
    upstreamText = result.upstreamText;
    upstreamStatus = result.status;
    if (upstreamStatus >= 200 && upstreamStatus < 300) {
      success = true;
      console.log("[session-imagen] using model", model);
      break;
    }
    console.error("[session-imagen] model attempt failed", { model, upstreamStatus });
  }
  if (!success) {
    return new Response(upstreamText || "Imagen request failed", {
      status: upstreamStatus,
      headers: corsHeaders,
    });
  }

  let imageBase64: string | null = null;
  try {
    const payload = JSON.parse(upstreamText) as Record<string, unknown>;
    const predictions = payload["predictions"];
    if (Array.isArray(predictions) && predictions.length > 0) {
      const first = predictions[0] as Record<string, unknown>;
      const direct = first["bytesBase64Encoded"];
      if (typeof direct === "string" && direct.length > 0) {
        imageBase64 = direct;
      }
      if (!imageBase64) {
        const mimeWrapper = first["mimeType"];
        const bytesWrapper = first["image"];
        if (typeof bytesWrapper === "object" && bytesWrapper !== null) {
          const nested = (bytesWrapper as Record<string, unknown>)["bytesBase64Encoded"];
          if (typeof nested === "string" && nested.length > 0) {
            imageBase64 = nested;
          }
        }
        if (!imageBase64 && typeof mimeWrapper === "string") {
          // no-op; preserve parsing branch for future schema variants
        }
      }
    }
  } catch {
    return new Response("Invalid Imagen response format", {
      status: 502,
      headers: corsHeaders,
    });
  }

  if (!imageBase64) {
    return new Response("Imagen did not return an image", {
      status: 502,
      headers: corsHeaders,
    });
  }
  console.log("[session-imagen] image generated", {
    base64Length: imageBase64.length,
    model: IMAGEN_MODEL,
  });

  const response = {
    imageBase64,
    mimeType: "image/png",
    model: IMAGEN_MODEL,
  };

  return new Response(JSON.stringify(response), {
    status: 200,
    headers: new Headers({
      ...Object.fromEntries(corsHeaders.entries()),
      "content-type": "application/json",
    }),
  });
});
