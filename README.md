# Scribe Clerk

Transcribe audio locally with [whisper.cpp](https://github.com/ggerganov/whisper.cpp), then optionally summarize transcripts through your Notion pipeline — no cloud transcription, no special permissions.

## Requirements

- macOS 14+
- `whisper-cli` (Homebrew: `brew install whisper-cpp`)
- GGML models in `~/whisper-models/` (defaults to `ggml-medium.bin`)

## Build

```bash
cd ~/Repos/voice-memo-transcriber
./scripts/build-app.sh
open dist/Scribe\ Clerk.app
```

## How to use

**Drop audio**
1. Drop one or many files onto the window (Finder, Voice Memos, etc.)
2. Choose language and model, then transcribe

**Other ways**
- Drag from Voice Memos into the window
- Click **+** in the sidebar to pick files

Supports M4A, MP3, WAV, FLAC, OGG, and more.

**Summarize to Notion**

After transcribing, click **Summarize** to export the transcript into [meeting-summaries-to-notion](~/Repos/meeting-summaries-to-notion) and run its OpenRouter → Notion pipeline. Choose meeting notes or project updates and the summary language in the sheet.

## Development with Xcode

```bash
./scripts/open-xcode.sh
```

Press **⌘R** to build and run. For the `.app` bundle:

```bash
./scripts/build-app.sh
```

## Settings (⌘,)

- Whisper binary path (default: `/opt/homebrew/bin/whisper-cli`)
- Default model path (default: `~/whisper-models/ggml-medium.bin`)
- Meeting summaries repo (default: `~/Repos/meeting-summaries-to-notion`)
- Deno binary (default: `/opt/homebrew/bin/deno`)
- Default summarizer pipeline (meeting notes or project updates)

Transcripts are saved in `~/Library/Application Support/ScribeClerk/transcripts/`.

If you used the previous **Voice Memo Transcriber** build, existing transcripts are migrated automatically on first launch.
