import { markdownToBlocks } from "npm:@tryfabric/martian@1.2.4";

const MAX_CHILDREN_PER_REQUEST = 100;
const MAX_RICH_TEXT_LENGTH = 2000;

export interface CreateNotionDocumentOptions {
  properties?: Record<string, unknown>;
  includeAttendees?: boolean;
  titlePropertyName?: string;
  additionalProperties?: Record<string, unknown>;
  transcript?: string;
  transcriptPageTitle?: string;
}

function notionHeaders(notionApiKey: string): Record<string, string> {
  return {
    Authorization: `Bearer ${notionApiKey}`,
    "Notion-Version": "2022-06-28",
    "Content-Type": "application/json",
  };
}

function textToParagraphBlocks(text: string): unknown[] {
  const blocks: unknown[] = [];
  const paragraphs = text.split(/\n{2,}/);

  for (const paragraph of paragraphs) {
    const trimmed = paragraph.trim();
    if (!trimmed) continue;

    for (let index = 0; index < trimmed.length; index += MAX_RICH_TEXT_LENGTH) {
      const chunk = trimmed.slice(index, index + MAX_RICH_TEXT_LENGTH);
      blocks.push({
        object: "block",
        type: "paragraph",
        paragraph: {
          rich_text: [{ type: "text", text: { content: chunk } }],
        },
      });
    }
  }

  if (blocks.length === 0 && text.trim()) {
    const trimmed = text.trim();
    for (let index = 0; index < trimmed.length; index += MAX_RICH_TEXT_LENGTH) {
      const chunk = trimmed.slice(index, index + MAX_RICH_TEXT_LENGTH);
      blocks.push({
        object: "block",
        type: "paragraph",
        paragraph: {
          rich_text: [{ type: "text", text: { content: chunk } }],
        },
      });
    }
  }

  return blocks;
}

function createTranscriptLinkBlocks(transcriptPageId: string): unknown[] {
  return [
    {
      object: "block",
      type: "paragraph",
      paragraph: {
        rich_text: [
          {
            type: "text",
            text: { content: "Original transcript: " },
          },
          {
            type: "mention",
            mention: {
              type: "page",
              page: { id: transcriptPageId },
            },
          },
        ],
      },
    },
    {
      object: "block",
      type: "divider",
      divider: {},
    },
  ];
}

async function appendBlocks(
  blockId: string,
  children: unknown[],
  requestHeaders: Record<string, string>,
): Promise<void> {
  const appendUrlBase = "https://api.notion.com/v1/blocks";

  for (
    let index = 0;
    index < children.length;
    index += MAX_CHILDREN_PER_REQUEST
  ) {
    const chunk = children.slice(index, index + MAX_CHILDREN_PER_REQUEST);
    const appendResponse = await fetch(
      `${appendUrlBase}/${blockId}/children`,
      {
        method: "PATCH",
        headers: requestHeaders,
        body: JSON.stringify({ children: chunk }),
      },
    );

    if (!appendResponse.ok) {
      const appendErrorText = await appendResponse.text();
      throw new Error(
        `Failed to append Notion blocks: ${appendResponse.statusText}, ${appendErrorText}`,
      );
    }
  }
}

async function createTranscriptSubPage(
  parentPageId: string,
  transcript: string,
  transcriptPageTitle: string,
  requestHeaders: Record<string, string>,
): Promise<string> {
  const transcriptBlocks = textToParagraphBlocks(transcript);
  const initialChildren = transcriptBlocks.slice(0, MAX_CHILDREN_PER_REQUEST);

  const response = await fetch("https://api.notion.com/v1/pages", {
    method: "POST",
    headers: requestHeaders,
    body: JSON.stringify({
      parent: { page_id: parentPageId },
      properties: {
        title: {
          title: [{ text: { content: transcriptPageTitle } }],
        },
      },
      ...(initialChildren.length > 0 ? { children: initialChildren } : {}),
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(
      `Failed to create transcript sub-page: ${response.statusText}, ${errorText}`,
    );
  }

  const responseData = await response.json();
  const transcriptPageId: string = responseData.id;

  await appendBlocks(
    transcriptPageId,
    transcriptBlocks.slice(MAX_CHILDREN_PER_REQUEST),
    requestHeaders,
  );

  console.error("Transcript sub-page created in Notion.");
  return transcriptPageId;
}

export async function createNotionDocument(
  title: string,
  content: string,
  userId: string | undefined,
  notionDatabaseId: string,
  notionApiKey: string,
  options: CreateNotionDocumentOptions = {},
): Promise<string> {
  const shouldIncludeAttendees = options.includeAttendees ?? Boolean(userId);
  const titlePropertyName = options.titlePropertyName ?? "Name";
  const transcript = options.transcript?.trim();
  const transcriptPageTitle = options.transcriptPageTitle ?? "Transcript";

  const defaultProperties: Record<string, unknown> = {
    [titlePropertyName]: { title: [{ text: { content: title } }] },
    ...(shouldIncludeAttendees && userId
      ? { Attendees: { people: [{ object: "user", id: userId }] } }
      : {}),
    ...(options.additionalProperties ?? {}),
  };

  const properties = options.properties ?? defaultProperties;
  const summaryBlocks = await markdownToBlocks(content);
  const requestHeaders = notionHeaders(notionApiKey);

  const response = await fetch("https://api.notion.com/v1/pages", {
    method: "POST",
    headers: requestHeaders,
    body: JSON.stringify({
      parent: { database_id: notionDatabaseId },
      properties,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Notion API error: ${response.statusText}, ${errorText}`);
  }

  const responseData = await response.json();
  const pageId: string = responseData.id;

  let pageBlocks: unknown[] = summaryBlocks;

  if (transcript) {
    const transcriptPageId = await createTranscriptSubPage(
      pageId,
      transcript,
      transcriptPageTitle,
      requestHeaders,
    );
    pageBlocks = [
      ...createTranscriptLinkBlocks(transcriptPageId),
      ...summaryBlocks,
    ];
  }

  await appendBlocks(pageId, pageBlocks, requestHeaders);

  const documentUrl = `https://notion.so/${responseData.id.replace(/-/g, "")}`;

  console.error("Document successfully created in Notion.");
  return documentUrl;
}
