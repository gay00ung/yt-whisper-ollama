#!/usr/bin/env bash
set -eo pipefail

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
# whisper.cpp (whisper-cli)
if ! command -v whisper-cli >/dev/null 2>&1; then
  echo "Installing whisper-cpp..."
  brew install whisper-cpp
fi
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

# GPU(Metal) 사용 확인
if sysctl -n machdep.cpu.brand_string 2>/dev/null | grep -q "Apple"; then
  echo "🚀 Apple Silicon detected - GPU acceleration enabled"
fi

# ---------- load config ----------
CONFIG_FILE="${HOME}/.yt_whisper.conf"
if [[ -f "$CONFIG_FILE" ]]; then
  echo "Loading config from $CONFIG_FILE"
  source "$CONFIG_FILE"
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
read -r -p "Model [${WHISPER_MODEL:-3}]: " MODEL_CHOICE
MODEL_CHOICE="${MODEL_CHOICE:-${WHISPER_MODEL:-3}}"

case "$MODEL_CHOICE" in
  1) WHISPER_MODEL="tiny" ;;
  2) WHISPER_MODEL="base" ;;
  3) WHISPER_MODEL="small" ;;
  4) WHISPER_MODEL="medium" ;;
  5) WHISPER_MODEL="large" ;;
  6) WHISPER_MODEL="turbo" ;;
  *) WHISPER_MODEL="small" ;;
esac

# Whisper는 자동 언어 감지 사용
TRANSCRIPT_LANG="auto"

# CPU 코어 수 감지 (whisper-cli 스레드 최적화용)
CPU_CORES=$(sysctl -n hw.ncpu 2>/dev/null || echo 4)
echo "💻 CPU cores detected: $CPU_CORES"

# whisper.cpp 모델 파일 확인 및 다운로드
WHISPER_MODEL_DIR="$HOME/.whisper-cpp-models"
mkdir -p "$WHISPER_MODEL_DIR"

# 모델명을 실제 파일명으로 매핑
case "$WHISPER_MODEL" in
  large)
    MODEL_FILENAME="ggml-large-v3.bin"
    ;;
  turbo)
    MODEL_FILENAME="ggml-large-v3-turbo.bin"
    ;;
  *)
    MODEL_FILENAME="ggml-${WHISPER_MODEL}.bin"
    ;;
esac

MODEL_FILE="$WHISPER_MODEL_DIR/$MODEL_FILENAME"

if [[ ! -f "$MODEL_FILE" ]]; then
  echo "📥 Downloading whisper.cpp model: $WHISPER_MODEL ($MODEL_FILENAME)..."
  echo "   This is a one-time download (~${WHISPER_MODEL} size varies)"
  
  MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILENAME"
  
  if ! curl -L -o "$MODEL_FILE" "$MODEL_URL" 2>&1 | grep -v "^  " ; then
    echo "ERROR: Failed to download whisper.cpp model"
    echo "Please download manually from: $MODEL_URL"
    exit 1
  fi
  
  echo "✅ Model downloaded successfully"
else
  echo "✅ whisper.cpp model found: $WHISPER_MODEL ($MODEL_FILENAME)"
fi

echo "Choose Ollama model:"
echo "  1) llama3.1  (기본값, 균형잡힌 성능)"
echo "  2) qwen2.5   (기술 요약에 최적)"
echo "  3) mistral   (빠른 요약)"
echo "  4) llama3.2  (빠른 요약)"
echo "  5) phi4      (저사양용)"
echo "  6) custom    (직접 입력)"
read -r -p "Model [${OLLAMA_MODEL:-1}]: " OLLAMA_CHOICE
OLLAMA_CHOICE="${OLLAMA_CHOICE:-1}"

case "$OLLAMA_CHOICE" in
  1) OLLAMA_MODEL="llama3.1" ;;
  2) OLLAMA_MODEL="qwen2.5" ;;
  3) OLLAMA_MODEL="mistral" ;;
  4) OLLAMA_MODEL="llama3.2" ;;
  5) OLLAMA_MODEL="phi4" ;;
  6) 
    read -r -p "Enter model name: " CUSTOM_MODEL
    OLLAMA_MODEL="${CUSTOM_MODEL:-llama3.1}"
    ;;
  *) OLLAMA_MODEL="llama3.1" ;;
esac

# Ollama 모델 존재 확인 및 자동 pull
echo "Checking Ollama model: $OLLAMA_MODEL"
if ! ollama list | grep -q "^${OLLAMA_MODEL}" ; then
  echo "Model '$OLLAMA_MODEL' not found locally. Pulling..."
  if ! ollama pull "$OLLAMA_MODEL"; then
    echo "ERROR: Failed to pull model '$OLLAMA_MODEL'."
    echo "Please check model name or network connection."
    exit 1
  fi
  echo "✓ Model '$OLLAMA_MODEL' ready"
fi

echo "Choose summary style:"
echo "  1) 표준 (7줄 요약 + 5개 포인트 + 결론) [기본값]"
echo "  2) 간단 (3줄 핵심 요약)"
echo "  3) 상세 (챕터별 구분 + 타임라인)"
echo "  4) 학습용 (Q&A 형식)"
echo "  5) 블로그 (서론-본론-결론)"
echo "  6) 강의 노트 (완전한 이해 가능, 최고 상세) [BEST]"
read -r -p "Style [${SUMMARY_STYLE:-1}]: " STYLE_CHOICE
SUMMARY_STYLE="${STYLE_CHOICE:-${SUMMARY_STYLE:-1}}"

echo "Choose summary language:"
echo "  1) 한국어 [기본값]"
echo "  2) English"
read -r -p "Language [1]: " SUMMARY_LANG_CHOICE
SUMMARY_LANG_CHOICE="${SUMMARY_LANG_CHOICE:-1}"

if [[ "$SUMMARY_LANG_CHOICE" == "2" ]]; then
  SUMMARY_LANG="en"
else
  SUMMARY_LANG="ko"
fi

echo "🌐 Summary language: $SUMMARY_LANG"

read -r -p "Output directory [${OUTPUT_BASE:-~/Desktop}]: " OUTPUT_INPUT
# 입력이 비어있으면 기본값 사용
if [[ -z "$OUTPUT_INPUT" ]]; then
  OUTPUT_BASE="${OUTPUT_BASE:-${HOME}/Desktop}"
else
  OUTPUT_BASE="$OUTPUT_INPUT"
fi
# Expand ~ to home directory
OUTPUT_BASE="${OUTPUT_BASE/#\~/$HOME}"

# ---------- workdir ----------
# 출력 디렉토리가 없으면 생성
mkdir -p "$OUTPUT_BASE"

# 디스크 공간 체크 (최소 1GB 필요)
AVAILABLE_MB=$(df -Pk "$OUTPUT_BASE" | tail -1 | awk '{print int($4/1024)}')
if [[ $AVAILABLE_MB -lt 1024 ]]; then
  echo "ERROR: Insufficient disk space. Available: ${AVAILABLE_MB}MB, Required: 1024MB"
  exit 1
fi

OUTDIR="${OUTPUT_BASE}/yt_whisper_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$OUTDIR"
cd "$OUTDIR"

# ---------- download ----------
echo "==> Downloading audio..."
# pipefail 때문에 ls 실패 시 스크립트 종료되는 것 방지
set +e
MP3="$(find . -maxdepth 1 -name "*.mp3" -type f 2>/dev/null | head -n 1 | sed 's|^\./||')"
set -e

if [[ -n "$MP3" ]]; then
  echo "Found existing MP3: $MP3"
  read -r -p "Use existing file? (y/n) [y]: " USE_EXISTING
  USE_EXISTING="${USE_EXISTING:-y}"
  if [[ "$USE_EXISTING" != "y" ]]; then
    rm -f *.mp3
    echo "📥 Downloading audio (optimized)..."
    yt-dlp -x --audio-format mp3 --audio-quality 0 --no-playlist --concurrent-fragments 4 "$URL"
    set +e
    MP3="$(find . -maxdepth 1 -name "*.mp3" -type f 2>/dev/null | head -n 1 | sed 's|^\./||')"
    set -e
    if [[ -z "$MP3" ]]; then
      echo "ERROR: Download failed. Check URL or network connection."
      exit 1
    fi
  fi
else
  echo "📥 Downloading audio (optimized)..."
  yt-dlp -x --audio-format mp3 --audio-quality 0 --no-playlist --concurrent-fragments 4 "$URL"

  set +e
  MP3="$(find . -maxdepth 1 -name "*.mp3" -type f 2>/dev/null | head -n 1 | sed 's|^\./||')"
  set -e

  if [[ -z "$MP3" ]]; then
    echo ""
    echo "ERROR: Download failed. Check URL or network connection."
    echo "Try: brew upgrade yt-dlp"
    exit 1
  fi
fi

[[ -z "${MP3}" ]] && { echo "ERROR: mp3 not created."; exit 1; }

# ---------- whisper ----------
set +e
TXT="$(find . -maxdepth 1 -name "*.txt" -type f 2>/dev/null | head -n 1 | sed 's|^\./||')"
set -e

if [[ -n "$TXT" ]]; then
  echo "Found existing transcript: $TXT"
  read -r -p "Use existing transcript? (y/n) [y]: " USE_EXISTING_TXT
  USE_EXISTING_TXT="${USE_EXISTING_TXT:-y}"
  if [[ "$USE_EXISTING_TXT" != "y" ]]; then
    rm -f *.txt
    echo "==> Transcribing with whisper.cpp ($WHISPER_MODEL) [5x faster]..."
    # whisper.cpp 사용 (Python whisper보다 5~10배 빠름)
    # 모델명을 실제 파일명으로 매핑
    case "$WHISPER_MODEL" in
      large)
        MODEL_FILENAME="ggml-large-v3.bin"
        ;;
      turbo)
        MODEL_FILENAME="ggml-large-v3-turbo.bin"
        ;;
      *)
        MODEL_FILENAME="ggml-${WHISPER_MODEL}.bin"
        ;;
    esac
    MODEL_FILE="$HOME/.whisper-cpp-models/$MODEL_FILENAME"
    LANG_CODE="${TRANSCRIPT_LANG}"
    [[ "$LANG_CODE" == "auto" ]] && LANG_CODE="auto"
    
    # -nt: 타임스탬프 출력 안 함, -np: 진행률 표시 안 함, -t: 스레드 수
    # stdout만 /dev/null로 (전사 텍스트 숨김), stderr는 표시(모델 로딩 등)
    echo "🎙️  Transcribing with $CPU_CORES threads..."
    whisper-cli -m "$MODEL_FILE" -l "$LANG_CODE" -f "$MP3" -t "$CPU_CORES" -otxt -of "${MP3%.mp3}" -nt -np > /dev/null
    set +e
    TXT="$(find . -maxdepth 1 -name "*.txt" -type f 2>/dev/null | head -n 1 | sed 's|^\./||')"
    set -e
  fi
else
  echo "==> Transcribing with whisper.cpp ($WHISPER_MODEL) [5x faster]..."
  # whisper.cpp 사용 (Python whisper보다 5~10배 빠름)
  # 모델명을 실제 파일명으로 매핑
  case "$WHISPER_MODEL" in
    large)
      MODEL_FILENAME="ggml-large-v3.bin"
      ;;
    turbo)
      MODEL_FILENAME="ggml-large-v3-turbo.bin"
      ;;
    *)
      MODEL_FILENAME="ggml-${WHISPER_MODEL}.bin"
      ;;
  esac
  MODEL_FILE="$HOME/.whisper-cpp-models/$MODEL_FILENAME"
  LANG_CODE="${TRANSCRIPT_LANG}"
  [[ "$LANG_CODE" == "auto" ]] && LANG_CODE="auto"
  
  # -nt: 타임스탬프 출력 안 함, -np: 진행률 표시 안 함, -t: 스레드 수
  # stdout만 /dev/null로 (전사 텍스트 숨김), stderr는 표시(모델 로딩 등)
  echo "🎙️  Transcribing with $CPU_CORES threads..."
  whisper-cli -m "$MODEL_FILE" -l "$LANG_CODE" -f "$MP3" -t "$CPU_CORES" -otxt -of "${MP3%.mp3}" -nt -np > /dev/null
  set +e
  TXT="$(find . -maxdepth 1 -name "*.txt" -type f 2>/dev/null | head -n 1 | sed 's|^\./||')"
  set -e
fi

[[ -z "${TXT}" ]] && { echo "ERROR: transcript not created."; exit 1; }

# ---------- summarize ----------
echo "📝 Summarizing with Ollama ($OLLAMA_MODEL)..."
echo "⏳ This may take a few minutes for long videos..."

# 스타일별 프롬프트 생성
case "$SUMMARY_STYLE" in
  1) # 표준
    if [[ "$SUMMARY_LANG" == "ko" ]]; then
      SUMMARY_PROMPT=$'아래 유튜브 영상의 전사 텍스트를 읽고 실제 내용을 바탕으로 요약해라. 템플릿이나 빈 칸 없이 구체적인 내용으로 채워라.\n\n형식:\n1. 핵심 요약 (7줄): 영상의 주요 내용을 7개 문장으로 요약\n2. 주요 포인트 (5개): 중요한 포인트 5개를 불릿으로 나열\n3. 한 줄 결론: 영상의 핵심 메시지를 한 문장으로 표현\n\n한국어로 작성하고, 실제 영상 내용을 구체적으로 담아라.'
    else
      SUMMARY_PROMPT=$'Read the YouTube video transcript below and summarize the ACTUAL content. Fill in with specific details from the video, not templates or blanks.\n\nFormat:\n1. Core Summary (7 lines): Summarize the main content in 7 sentences\n2. Key Points (5 items): List 5 important points as bullets\n3. One-line Conclusion: Express the core message in one sentence\n\nWrite in English and include specific details from the actual video content.'
    fi
    ;;
  2) # 간단
    if [[ "$SUMMARY_LANG" == "ko" ]]; then
      SUMMARY_PROMPT=$'다음은 유튜브 영상 전사 텍스트다.\n가장 중요한 핵심 내용 3줄로 간단명료하게 요약해라.\n한국어로 출력해라.'
    else
      SUMMARY_PROMPT=$'This is a YouTube video transcript.\nSummarize the most important points in 3 concise lines.\nRespond in English.'
    fi
    ;;
  3) # 상세
    if [[ "$SUMMARY_LANG" == "ko" ]]; then
      SUMMARY_PROMPT=$'다음은 유튜브 영상 전사 텍스트다.\n다음 형식으로 상세하게 정리해라:\n1) 전체 개요 (3줄)\n2) 챕터별 주요 내용 (최소 5개 챕터, 각 챕터마다 제목과 2-3줄 설명)\n3) 핵심 인사이트 (5개)\n4) 최종 결론\n한국어로 출력해라.'
    else
      SUMMARY_PROMPT=$'This is a YouTube video transcript.\nProvide a detailed breakdown:\n1) Overview (3 lines)\n2) Chapter-by-chapter breakdown (at least 5 chapters, with title and 2-3 line description each)\n3) Key insights (5 points)\n4) Final conclusion\nRespond in English.'
    fi
    ;;
  4) # 학습용
    if [[ "$SUMMARY_LANG" == "ko" ]]; then
      SUMMARY_PROMPT=$'다음은 유튜브 영상 전사 텍스트다.\n학습 자료 형식으로 정리해라:\n1) 핵심 질문 5개와 각각의 답변\n2) 중요한 개념/용어 설명 (5개)\n3) 실전 활용 팁 (3개)\n4) 추가 학습이 필요한 주제\n한국어로 출력해라.'
    else
      SUMMARY_PROMPT=$'This is a YouTube video transcript.\nFormat as study material:\n1) 5 key questions and answers\n2) Important concepts/terms explained (5 items)\n3) Practical tips (3 items)\n4) Topics for further study\nRespond in English.'
    fi
    ;;
  5) # 블로그
    if [[ "$SUMMARY_LANG" == "ko" ]]; then
      SUMMARY_PROMPT=$'다음은 유튜브 영상 전사 텍스트다.\n블로그 포스팅 형식으로 작성해라:\n1) 서론 (흥미를 끄는 도입부, 2-3줄)\n2) 본론 (주요 내용을 3-4개 섹션으로 나눠서 각 섹션마다 제목과 설명)\n3) 결론 (핵심 메시지와 행동 촉구, 2-3줄)\n한국어로 출력해라.'
    else
      SUMMARY_PROMPT=$'This is a YouTube video transcript.\nWrite in blog post format:\n1) Introduction (engaging opening, 2-3 lines)\n2) Body (divide into 3-4 sections with titles and descriptions)\n3) Conclusion (key message and call-to-action, 2-3 lines)\nRespond in English.'
    fi
    ;;
  6) # 강의 노트 (최고 상세)
    if [[ "$SUMMARY_LANG" == "ko" ]]; then
      SUMMARY_PROMPT='
        아래는 강의/강연 영상의 전사 텍스트이다.
        요약본만 읽어도 영상을 직접 본 것과 동일한 수준으로
        논리 흐름, 핵심 주장, 근거, 결론을 완전히 이해할 수 있도록 정리하라.

        ⚠️ 필수 품질 규칙 (반드시 준수):
        - 추상적인 표현(예: 중요하다, 의미 있다, 필요하다, 새로운 시각)은
          반드시 구체적 근거(사례, 연도, 수치, 인물, 실험, 기술)와 함께 서술할 것
        - 원문에 등장하는 핵심 개념, 역사적 사건, 기술적 전환점은 절대 생략하지 말 것
        - 요약이 아니라 “내용 재구성” 수준으로 작성할 것
        - 동일한 일반론을 다른 말로 반복하지 말 것

        다음 형식으로 작성하라:

        # [제목]

        ## Executive Summary
        - 정확히 3–4문장
        - 배경 → 문제 정의 → 핵심 접근/전환점 → 결론 순서로 작성

        ## Takeaway
        - 1–2문장
        - 이 강의/강연이 주장하는 **단 하나의 핵심 메시지**를 명확히 서술

        ## Key Takeaways
        - 7–10개 불릿
        - 각 불릿에는 반드시 다음 중 최소 2개 포함:
          · 구체적 사례
          · 연도 또는 수치
          · 실험/연구 결과
          · 실제 응용 또는 영향

        ## Detailed Summary
        ### 섹션별 상세 정리:
        1. 소개 / 배경
          - 왜 이 강의가 등장했는지
          - 기존 접근의 한계는 무엇이었는지
        2. 주요 개념 1
          - 개념 정의
          - 실제 사례 또는 실험
          - 기존 방법과의 차이
        3. 주요 개념 2
          (동일 구조 반복)
        4. 방법론 / 시스템 / 접근법
          - 사용된 기술, 모델, 실험 환경
          - 왜 이 선택이 핵심이었는지

        (필요 시 표 형식 사용)

        ## Final Thought
        - 2–3문장
        - 분야/사회에 대한 구체적 영향
        - 남아있는 과제 또는 미해결 질문
        
        ⚠️ 모든 내용을 한국어로 작성하라. 영어를 사용하지 말 것.
      '
    else
      SUMMARY_PROMPT='
        Below is a transcript of a lecture or talk.
        Summarize it so thoroughly that a reader who ONLY reads the summary
        can fully understand the original content, logic, and conclusions.

        ⚠️ Mandatory quality rules (must follow):
        - Avoid vague statements (e.g., “important,” “meaningful,” “novel”) unless
          they are supported by concrete evidence (examples, years, numbers, experiments, methods)
        - Do NOT omit key concepts, historical events, or technical turning points from the original content
        - This is NOT a high-level abstract; reconstruct the content in detail
        - Do NOT fill sections with generic or repetitive statements

        Use the following format:

        # [Title]

        ## Executive Summary
        - Exactly 3–4 sentences
        - Write in this order: background → problem → key approach or turning point → conclusion

        ## Takeaway
        - 1–2 sentences
        - Clearly state the single most important claim of the lecture

        ## Key Takeaways
        - 7–10 bullet points
        - Each bullet must include at least two of the following:
          · Concrete examples
          · Years or numerical values
          · Experimental or research findings
          · Real-world applications or impact

        ## Detailed Summary
        ### Break down by sections:
        1. Introduction / Background
          - Why this lecture or research emerged
          - Limitations of previous approaches
        2. Main Concept 1
          - Definition
          - Supporting example or experiment
          - How it differs from prior methods
        3. Main Concept 2
          (Repeat the same structure)
        4. Method / System / Approach
          - Algorithms, models, or experimental setup
          - Why this approach was necessary or effective

        (Use tables where appropriate)

        ## Final Thought
        - 2–3 sentences
        - Concrete impact on the field
        - Remaining challenges or open questions
      '
    fi
    ;;
  *) # 기본값 (표준)
    if [[ "$SUMMARY_LANG" == "ko" ]]; then
      SUMMARY_PROMPT=$'다음은 유튜브 영상 전사 텍스트다.\n1) 핵심 요약 7줄\n2) 주요 포인트 5개 불릿\n3) 한 줄 결론\n한국어로 출력해라.'
    else
      SUMMARY_PROMPT=$'This is a YouTube video transcript.\n1) Core summary in 7 lines\n2) 5 key bullet points\n3) One-line conclusion\nRespond in English.'
    fi
    ;;
esac

echo "� Summarizing with Ollama ($OLLAMA_MODEL)..."
echo "⏳ This may take a few minutes for long videos..."

cat "$TXT" | ollama run "$OLLAMA_MODEL" "$SUMMARY_PROMPT" > summary.txt

# ---------- done ----------
echo ""
echo "DONE ✅"
echo "Folder: $OUTDIR"
echo "Files:"
ls -1
echo "Summary -> summary.txt"
