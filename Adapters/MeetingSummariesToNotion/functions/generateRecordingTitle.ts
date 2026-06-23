import { getOpenRouterSummary } from "./getOpenRouterSummary.ts";
import { DEFAULT_SUMMARY_MODEL } from "../config/summaryModels.ts";
import { applyGermanTitleFlag } from "./inferDocumentTitle.ts";

const TITLE_PROMPT = `You generate a short, descriptive title for a meeting recording based on its transcript.

Rules:
- One line only, in English.
- With a clear project or client: {Project} {Meeting type} with {Names}
- Without a clear project or client: {Meeting type} with {Names}
- Meeting type: infer from context — Meeting, Alignment, Check-in, Kick-off, Workshop, Review, Stand-up, Sync, Interview, Retro, Planning, Demo, etc.
- Project: client name, product name, or project name only when clearly discussed. Use the name people actually used.
- Names: comma-separated first names of clearly identifiable participants. Use "and" before the last name when there are three or more. If no names are clear, omit the names part.
- Examples: Acme Alignment with Thomas and Claudia, Ask Sona Kick-off with Dan, Check-in with Thomas and Claudia, Planning with Dan
- Maximum 80 characters.
- Return ONLY the title text, no quotes, no markdown, no explanation.`;

function normalizeTitle(raw: string): string {
  return raw
    .replace(/^["'`]+|["'`]+$/g, "")
    .replace(/\s+/g, " ")
    .trim()
    .split("\n")[0]
    ?.trim() ?? "";
}

function detectTranscriptLanguage(transcript: string): "english" | "german" {
  const sample = transcript.slice(0, 2500).toLowerCase();
  if (/[äöüß]/.test(sample)) return "german";

  const germanWords = sample.match(
    /\b(und|der|die|das|ist|sind|wir|nicht|auch|mit|für|auf|eine|einem|werden|haben|können|über|beim|dass|wurde|waren|geht|machen|müssen|dann|aber|oder|besprochen|entschieden|aufgabe|nächste|keine|schon|noch|sehr|ganz|zwischen)\b/g,
  )?.length ?? 0;

  const englishWords = sample.match(
    /\b(the|and|is|are|was|were|with|for|that|this|have|has|will|would|should|about|between|discussed|decided|task|next|none)\b/g,
  )?.length ?? 0;

  return germanWords > englishWords ? "german" : "english";
}

export async function generateRecordingTitle(options: {
  transcript: string;
  apiKey: string;
  fallback: string;
}): Promise<string> {
  const excerpt = options.transcript.slice(0, 12000);
  if (!excerpt.trim()) {
    return options.fallback;
  }

  const raw = await getOpenRouterSummary({
    systemPrompt: TITLE_PROMPT,
    content: excerpt,
    apiKey: options.apiKey,
    model: DEFAULT_SUMMARY_MODEL.model,
    maxTokens: 80,
    temperature: 0.3,
    userMessage:
      "Generate a title for the following meeting transcript using your system instructions:\n\n",
  });

  const title = normalizeTitle(raw);
  if (!title) {
    return options.fallback;
  }

  return detectTranscriptLanguage(excerpt) === "german"
    ? applyGermanTitleFlag(title)
    : title;
}
