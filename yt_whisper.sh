#!/usr/bin/env bash
set -euo pipefail

# ---------- utils ----------
has() { command -v "$1" >/dev/null 2>&1; }

install_brew() {
  if ! has brew; then
    echo "==> Homebrew not found. Installing..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
}

ensure() {
  local bin="$1"
  local formula="$2"
  if ! has "$bin"; then
    echo "==> Installing $formula..."
    brew install "$formula"
  fi
}

ensure_cask() {
  local app="$1"
  local cask="$2"
  if ! ls /Applications | grep -qi "$app"; then
    echo "==> Installing $cask (app)..."
    brew install --cask "$cask"
  fi
}

# ---------- bootstrap ----------
install_brew
ensure yt-dlp yt-dlp
ensure ffmpeg ffmpeg
ensure whisper openai-whisper
ensure ollama ollama

# Ollama server up?
if ! ollama list >/dev/null 2>&1; then
  echo "==> Starting Ollama server..."
  # 앱이 있으면 실행, 없으면 serve
  if ls /Applications | grep -qi "Ollama"; then
    open -a Ollama
    sleep 3
  else
    ollama serve >/dev/null 2>&1 &
    sleep 3
  fi
fi

# ---------- input ----------
read -r -p "YouTube URL: " URL
[[ -z "${URL}" ]] && { echo "ERROR: URL is empty."; exit 1; }

echo "Choose Whisper model:"
echo "  1) tiny   (39M, ~10x speed, ~1GB RAM)"
echo "  2) base   (74M, ~7x speed, ~1GB RAM)"
echo "  3) small  (244M, ~4x speed, ~2GB RAM) [추천]"
echo "  4) medium (769M, ~2x speed, ~5GB RAM)"
echo "  5) large  (1550M, 1x speed, ~10GB RAM)"
echo "  6) turbo  (fastest, good quality)"
read -r -p "Model [3]: " MODEL_CHOICE
MODEL_CHOICE="${MODEL_CHOICE:-3}"

case "$MODEL_CHOICE" in
  1) WHISPER_MODEL="tiny" ;;
  2) WHISPER_MODEL="base" ;;
  3) WHISPER_MODEL="small" ;;
  4) WHISPER_MODEL="medium" ;;
  5) WHISPER_MODEL="large" ;;
  6) WHISPER_MODEL="turbo" ;;
  *) WHISPER_MODEL="small" ;;
esac

read -r -p "Language (ko/en/auto) [ko]: " LANG
LANG="${LANG:-ko}"

read -r -p "Ollama model [llama3.1]: " OLLAMA_MODEL
OLLAMA_MODEL="${OLLAMA_MODEL:-llama3.1}"

read -r -p "Output directory [~/Desktop]: " OUTPUT_BASE
OUTPUT_BASE="${OUTPUT_BASE:-${HOME}/Desktop}"
# Expand ~ to home directory
OUTPUT_BASE="${OUTPUT_BASE/#\~/$HOME}"

# ---------- workdir ----------
OUTDIR="${OUTPUT_BASE}/yt_whisper_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

# ---------- download ----------
echo "==> Downloading audio..."
yt-dlp -x --audio-format mp3 --audio-quality 0 --no-playlist "$URL"

MP3="$(ls -1 *.mp3 | head -n 1)"
[[ -z "${MP3}" ]] && { echo "ERROR: mp3 not created."; exit 1; }

# ---------- whisper ----------
echo "==> Transcribing with Whisper ($WHISPER_MODEL)..."
ARGS=( "$MP3" --task transcribe --model "$WHISPER_MODEL" --output_format txt --verbose False )
[[ "$LANG" != "auto" ]] && ARGS+=( --language "$LANG" )
whisper "${ARGS[@]}"

TXT="$(ls -1 *.txt | head -n 1)"
[[ -z "${TXT}" ]] && { echo "ERROR: transcript not created."; exit 1; }

# ---------- summarize ----------
echo "==> Summarizing with Ollama ($OLLAMA_MODEL)..."
if [[ "$LANG" == "ko" ]]; then
  SUMMARY_PROMPT=$'다음은 유튜브 영상 전사 텍스트다.\n1) 핵심 요약 7줄\n2) 주요 포인트 5개 불릿\n3) 한 줄 결론\n한국어로 출력해라.'
else
  SUMMARY_PROMPT=$'This is a YouTube video transcript.\n1) Core summary in 7 lines\n2) 5 key bullet points\n3) One-line conclusion\nRespond in English.'
fi
cat "$TXT" | ollama run "$OLLAMA_MODEL" "$SUMMARY_PROMPT" > summary.txt

# ---------- done ----------
echo ""
echo "DONE ✅"
echo "Folder: $OUTDIR"
echo "Files:"
ls -1
echo "Summary -> summary.txt"
