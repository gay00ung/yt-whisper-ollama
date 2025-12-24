# yt-whisper-ollama

<!-- Language: English -->
[🇰🇷 한국어](README.ko.md) | **🇺🇸 English**

A fully local YouTube transcription & summarization pipeline for macOS.

This script downloads audio from a YouTube video, transcribes it using OpenAI Whisper, and summarizes the transcript using a local LLM via Ollama — all **offline**, with no cloud APIs.

---

## Features

- Download audio from YouTube
- Transcribe speech to text using **Whisper (local)**
- Summarize the transcript using a **local LLM (Ollama)**
- Automatic dependency installation (Homebrew-based)
- macOS & Apple Silicon friendly
- No API keys, no external servers

---

## Requirements

- macOS (tested on Apple Silicon)
- Internet connection (only for downloading tools/models and YouTube audio)

Everything else is handled by the script.

---

## Tools Used

This script **does not include or redistribute** any third-party code or binaries.  
It only **invokes existing open-source tools via CLI**.

- **yt-dlp** — audio extraction from YouTube  
  License: Unlicense  
  https://github.com/yt-dlp/yt-dlp

- **FFmpeg** — audio format conversion  
  License: LGPL / GPL  
  Used only as an external command-line tool  
  https://ffmpeg.org/

- **OpenAI Whisper (CLI)** — speech-to-text transcription  
  License: MIT  
  https://github.com/openai/whisper

- **Ollama** — local LLM runner for summarization  
  License: Apache 2.0  
  https://ollama.com/

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/gay00ung/yt-whisper-ollama.git
cd yt-whisper-ollama
````

---

### 2. Make the script executable (important)

Depending on your environment, `chmod +x` may **not** work automatically when cloning.

If execution fails, run **one of the following**:

```bash
chmod +x yt_whisper.sh
```

If that still does not work:

```bash
bash yt_whisper.sh
```

(Using `bash` directly bypasses execute permission issues.)

---

## Usage

Run the script:

```bash
./yt_whisper.sh
```

or, if execution permission is blocked:

```bash
bash yt_whisper.sh
```

You will be prompted for:

1. **YouTube URL**
2. **Whisper model size**

   * `tiny` (39M, ~10x speed, ~1GB RAM)
   * `base` (74M, ~7x speed, ~1GB RAM)
   * `small` (244M, ~4x speed, ~2GB RAM) — **recommended**
   * `medium` (769M, ~2x speed, ~5GB RAM)
   * `large` (1550M, 1x speed, ~10GB RAM)
   * `turbo` (fastest, good quality)
3. **Language** (`ko`, `en`, or `auto`)
4. **Ollama model**

   * `llama3.1` (default, balanced performance)
   * `qwen2.5` (optimized for technical content)
   * `mistral` (fast summarization)
   * `llama3.2` (fast summarization)
   * `phi4` (low-resource)
   * `custom` (enter your own model name)
5. **Output directory** (default: `~/Desktop`)

---

## What the Script Does

1. Installs required tools if missing:

   * Homebrew
   * yt-dlp
   * ffmpeg
   * openai-whisper
   * ollama
2. Starts the Ollama server if not running
3. Downloads YouTube audio as MP3
4. Transcribes audio with Whisper
5. Summarizes the transcript using Ollama
6. Saves results to a timestamped folder in your chosen directory

---

## Output

A new folder will be created in your chosen directory (default: Desktop):

```
yt_whisper_YYYYMMDD_HHMMSS/
├── video_title.mp3
├── video_title.txt
└── summary.txt
```

* `*.txt` → full transcription
* `summary.txt` → summarized output

---

## License

This project is released under the **MIT License**.
See the `LICENSE` file for details.

Note: Third-party tools used by this script are governed by their respective licenses.

---

## Disclaimer

This script is intended for personal, educational, and research use.
Users are responsible for complying with YouTube’s Terms of Service and applicable copyright laws.

---

## Why Local?

* No API costs
* No data sent to external servers
* Works offline after setup
* Ideal for long talks, lectures, and technical content