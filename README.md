# Voice Memo Transcriber

Transcribe audio locally with [whisper.cpp](https://github.com/ggerganov/whisper.cpp) — no cloud, no special permissions.

## Requirements

- macOS 14+
- `whisper-cli` (Homebrew: `brew install whisper-cpp`)
- GGML models in `~/whisper-models/` (defaults to `ggml-medium.bin`)

## Build

```bash
cd ~/repos/voice-memo-transcriber
./scripts/build-app.sh
open dist/Voice\ Memo\ Transcriber.app
```

## How to use

**From Voice Memos**
1. Open Voice Memos and this app side by side
2. Drag a recording from the Voice Memos list onto the app window
3. Choose language and model, then transcribe

**Other ways**
- Drop any audio file onto the window (Finder, etc.)
- Click **+** in the toolbar to pick files

Supports M4A, MP3, WAV, FLAC, OGG, and more.

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

Transcripts are saved in `~/Library/Application Support/VoiceMemoTranscriber/transcripts/`.
