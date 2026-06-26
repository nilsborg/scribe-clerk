import { adapterPath } from "../paths.ts";

const DEFAULT_GLOSSARY_PATH = adapterPath("config", "glossary.md");

const WHISPER_PROMPT_MAX_CHARS = 800;

export interface GlossarySection {
  title: string;
  terms: string[];
}

export interface Glossary {
  sections: GlossarySection[];
}

function parseGlossaryMarkdown(content: string): Glossary {
  const sections: GlossarySection[] = [];
  let currentSection: GlossarySection | null = null;

  for (const line of content.split("\n")) {
    const headingMatch = line.match(/^##\s+(.+)$/);
    if (headingMatch) {
      currentSection = { title: headingMatch[1].trim(), terms: [] };
      sections.push(currentSection);
      continue;
    }

    const termMatch = line.match(/^-\s+(.+)$/);
    if (termMatch && currentSection) {
      const term = termMatch[1].trim();
      if (term) currentSection.terms.push(term);
    }
  }

  return {
    sections: sections.filter((section) => section.terms.length > 0),
  };
}

export async function loadGlossary(
  glossaryFilePath = DEFAULT_GLOSSARY_PATH,
): Promise<Glossary | null> {
  try {
    const content = await Deno.readTextFile(glossaryFilePath);
    const glossary = parseGlossaryMarkdown(content);
    return glossary.sections.length > 0 ? glossary : null;
  } catch (error) {
    if (error instanceof Deno.errors.NotFound) {
      return null;
    }
    throw error;
  }
}

export function formatGlossaryForSummary(glossary: Glossary): string {
  const sections = glossary.sections.filter(
    (section) => !/^people$/i.test(section.title),
  );
  if (sections.length === 0) return "";

  const lines = [
    "## Known terms",
    "Use these exact spellings only when the term is clearly spoken in the transcript.",
    "Do not add people, projects, or clients from this list to the summary unless they are actually discussed.",
  ];

  for (const section of sections) {
    lines.push(`\n### ${section.title}`);
    for (const term of section.terms) {
      lines.push(`- ${term}`);
    }
  }

  return lines.join("\n");
}

export function formatGlossaryForWhisper(glossary: Glossary): string {
  const terms = [
    ...new Set(glossary.sections.flatMap((section) => section.terms)),
  ];

  if (terms.length === 0) return "";

  const prompt = `Meeting about ${terms.join(", ")}.`;
  if (prompt.length <= WHISPER_PROMPT_MAX_CHARS) return prompt;

  let truncated = "Meeting about ";
  for (const term of terms) {
    const next = truncated === "Meeting about "
      ? `${truncated}${term}`
      : `${truncated}, ${term}`;
    if (next.length > WHISPER_PROMPT_MAX_CHARS - 1) break;
    truncated = next;
  }

  return `${truncated}.`;
}

export function appendGlossaryToPrompt(
  basePrompt: string,
  glossary: Glossary | null,
): string {
  if (!glossary) return basePrompt;
  const glossaryBlock = formatGlossaryForSummary(glossary);
  if (!glossaryBlock) return basePrompt;
  return `${basePrompt.trim()}\n\n${glossaryBlock}`;
}
