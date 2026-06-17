# Scribe Clerk

Transcribe audio locally with [whisper.cpp](https://github.com/ggerganov/whisper.cpp), keep a managed recording library, generate editable summaries, and publish to Notion.

## Requirements

- macOS 14+
- `whisper-cli` (Homebrew: `brew install whisper-cpp`)
- `deno` (Homebrew: `brew install deno`)
- GGML models in `~/whisper-models/` (defaults to `ggml-medium.bin`)
- Adapter `.env` with OpenRouter and Notion credentials (see `Adapters/MeetingSummariesToNotion/.env.example`)

## Build

```bash
cd ~/Repos/scribe-clerk
cp Adapters/MeetingSummariesToNotion/.env.example Adapters/MeetingSummariesToNotion/.env
./scripts/build-app.sh
open dist/Scribe\ Clerk.app
```

## Workflow

1. **Add** audio via drag & drop, file picker, or the inbox folder
2. **Import** from the inbox into your library
2. **Transcribe** with Whisper (auto-detect language by default)
3. **Summarize** into editable markdown (meeting notes or project updates, English or German)
4. **Publish** to Notion when ready (summary page + linked transcript sub-page)

### Inbox

Drop files in the app or point external tools (e.g. Audio Hijack) at:

`~/Library/Application Support/ScribeClerk/inbox/`

Recordings appear in the Inbox section. Click **Import** to move them into the managed library.

### Voice Memos

Drag recordings from Voice Memos into the app window.

## Library layout

`~/Library/Application Support/ScribeClerk/`

- `inbox/` — staging area for new recordings
- `recordings/{id}/` — managed audio, transcript, summaries, and metadata

## Development

```bash
./scripts/open-xcode.sh
```

Press **⌘R** to build and run.

## Settings (⌘,)

- Whisper binary and default model
- Deno binary path
- Adapter `.env` file path
- Default summarizer pipeline
