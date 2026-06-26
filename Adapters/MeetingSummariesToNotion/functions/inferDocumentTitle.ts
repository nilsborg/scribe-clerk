export interface DocumentTitleResult {
  title: string;
  content: string;
}

export type SummaryLanguage = "english" | "german";

const GERMAN_FLAG = "🇩🇪";

const SUGGESTED_TITLE_PATTERN =
  /(?:^|\n)#{1,3}\s*Suggested Title\s*\n+([^\n#]+(?:\n(?!\s*#{1,3}\s)[^\n#]+)*)/i;

function normalizeTitle(raw: string): string {
  return raw
    .replace(/^["'`]+|["'`]+$/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

export function stripSuggestedTitleSection(summary: string): string {
  return summary
    .replace(SUGGESTED_TITLE_PATTERN, "\n")
    .replace(/^\n+/, "")
    .trim();
}

export function applyGermanTitleFlag(title: string): string {
  const trimmed = title.trim();
  if (!trimmed || trimmed.startsWith(GERMAN_FLAG)) return trimmed;
  return `${GERMAN_FLAG} ${trimmed}`;
}

export function detectSummaryLanguage(summary: string): SummaryLanguage {
  if (
    /(?:^|\n)#{1,3}\s*(Zusammenfassung|Besprechungsnotizen|Entscheidungen|Aufgaben|Nächste Schritte|Was ist neu|Themen)\b/m
      .test(summary)
  ) {
    return "german";
  }

  const withoutEnglishSummary = summary.replace(
    /(?:^|\n)#{1,3}\s*English Summary[\s\S]*?(?=(?:^|\n)#{1,3}\s|\n##|$)/im,
    "",
  );
  const sample = withoutEnglishSummary.slice(0, 2500).toLowerCase();

  if (/[äöüß]/.test(sample)) return "german";

  const germanWords = sample.match(
    /\b(und|der|die|das|ist|sind|wir|nicht|auch|mit|für|auf|eine|einem|werden|haben|können|über|beim|dass|wurde|waren|geht|machen|müssen|dann|aber|oder|besprochen|entschieden|aufgabe|nächste|keine|schon|noch|sehr|ganz|zwischen)\b/g,
  )?.length ?? 0;

  const englishWords = sample.match(
    /\b(the|and|is|are|was|were|with|for|that|this|have|has|will|would|should|about|between|discussed|decided|task|next|none)\b/g,
  )?.length ?? 0;

  return germanWords > englishWords ? "german" : "english";
}

function finalizeTitle(title: string, language: SummaryLanguage): string {
  return language === "german" ? applyGermanTitleFlag(title) : title;
}

export function inferDocumentTitle(
  summary: string,
  fallback: string,
  options?: { language?: SummaryLanguage },
): DocumentTitleResult {
  const language = options?.language ?? detectSummaryLanguage(summary);
  const match = summary.match(SUGGESTED_TITLE_PATTERN);
  if (match) {
    const title = normalizeTitle(match[1]);
    if (title) {
      return {
        title: finalizeTitle(title, language),
        content: stripSuggestedTitleSection(summary),
      };
    }
  }

  return {
    title: finalizeTitle(fallback, language),
    content: summary,
  };
}
