export type ChatMessage = {
  role: string;
  content: string;
};

export type GlmChatRequest = {
  model: string;
  messages: ChatMessage[];
  temperature?: number;
  max_tokens?: number;
};

export type GlmChatResponse = {
  content: string;
  model: string;
  promptTokens: number;
  completionTokens: number;
};

function glm5MinorVersion(model: string): number | null {
  const match = model.trim().toLowerCase().match(/glm-5\.(\d+)/);
  if (!match) return null;
  return Number.parseInt(match[1], 10);
}

/** GLM-5.3+ always reasons; `thinking.type: disabled` is rejected. */
function thinkingFieldsForModel(model: string): Record<string, unknown> {
  const minor = glm5MinorVersion(model);
  if (minor !== null && minor >= 3) {
    return {
      thinking: { type: "enabled" },
      reasoning_effort: "low",
    };
  }
  return { thinking: { type: "disabled" } };
}

export async function callGlmChat(
  baseUrl: string,
  apiKey: string,
  body: GlmChatRequest
): Promise<GlmChatResponse> {
  const url = `${baseUrl.replace(/\/$/, "")}/chat/completions`;
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
      "Accept-Language": "en-US,en",
    },
    body: JSON.stringify({
      model: body.model,
      messages: body.messages,
      temperature: body.temperature ?? 0.7,
      max_tokens: body.max_tokens ?? 4096,
      stream: false,
      ...thinkingFieldsForModel(body.model),
    }),
  });

  const raw = await response.text();
  if (!response.ok) {
    const err = Object.assign(new Error(`GLM upstream error HTTP ${response.status}`), {
      status: response.status === 401 ? 502 : response.status,
      upstream: raw.slice(0, 200),
    });
    throw err;
  }

  const json = JSON.parse(raw) as {
    model?: string;
    choices?: Array<{ message?: { content?: string; reasoning_content?: string } }>;
    usage?: { prompt_tokens?: number; completion_tokens?: number };
  };

  const message = json.choices?.[0]?.message;
  const content =
    (message?.content && message.content.trim()) ||
    (message?.reasoning_content && message.reasoning_content.trim()) ||
    "";

  if (!content) {
    throw Object.assign(new Error("Empty model response"), { status: 502 });
  }

  return {
    content,
    model: json.model || body.model,
    promptTokens: json.usage?.prompt_tokens ?? 0,
    completionTokens: json.usage?.completion_tokens ?? 0,
  };
}
