export type OpenAiSpeechRequest = {
  input: string;
  voice?: string;
  model?: string;
  speed?: number;
};

export type OpenAiSpeechResult = {
  audio: Buffer;
  estimatedTokens: number;
};

const DEFAULT_MODEL = "tts-1-hd";
const DEFAULT_VOICE = "nova";

export async function callOpenAiSpeech(
  apiKey: string,
  request: OpenAiSpeechRequest
): Promise<OpenAiSpeechResult> {
  const input = request.input.trim().slice(0, 4096);
  if (!input) {
    throw Object.assign(new Error("input is required"), { status: 400 });
  }

  const response = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: request.model ?? DEFAULT_MODEL,
      input,
      voice: request.voice ?? DEFAULT_VOICE,
      response_format: "mp3",
      speed: clampSpeed(request.speed),
    }),
  });

  if (!response.ok) {
    const detail = (await response.text()).slice(0, 200);
    throw Object.assign(new Error(`OpenAI TTS failed: ${detail}`), {
      status: response.status >= 400 && response.status < 600 ? response.status : 502,
    });
  }

  const audio = Buffer.from(await response.arrayBuffer());
  if (audio.length === 0) {
    throw Object.assign(new Error("OpenAI TTS returned empty audio"), { status: 502 });
  }

  return {
    audio,
    estimatedTokens: Math.max(1, Math.ceil(input.length / 4)),
  };
}

function clampSpeed(value: number | undefined): number {
  if (typeof value !== "number" || Number.isNaN(value)) return 1;
  return Math.min(Math.max(value, 0.25), 4);
}
