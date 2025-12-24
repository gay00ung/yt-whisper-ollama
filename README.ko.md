# yt-whisper-ollama

<!-- Language: Korean -->
**🇰🇷 한국어** | [🇺🇸 English](README.md)

macOS를 위한 완전히 로컬 환경의 YouTube 음성 변환 및 요약 파이프라인입니다.

이 스크립트는 YouTube 동영상에서 오디오를 다운로드하고, OpenAI Whisper를 사용하여 음성을 텍스트로 변환하며, Ollama를 통해 로컬 LLM으로 요약합니다 — 모두 **오프라인**에서, 클라우드 API 없이 작동합니다.

---

## 주요 기능

- YouTube에서 오디오 다운로드
- **Whisper(로컬)**를 사용한 음성-텍스트 변환
- **로컬 LLM(Ollama)**을 사용한 트랜스크립트 요약
- 자동 의존성 설치 (Homebrew 기반)
- macOS 및 Apple Silicon 친화적
- API 키 불필요, 외부 서버 없음

---

## 요구사항

- macOS (Apple Silicon에서 테스트됨)
- 인터넷 연결 (도구/모델 다운로드 및 YouTube 오디오용)

나머지는 모두 스크립트가 처리합니다.

---

## 사용된 도구

이 스크립트는 타사 코드나 바이너리를 **포함하거나 재배포하지 않습니다**.  
오직 **CLI를 통해 기존 오픈소스 도구를 호출**할 뿐입니다.

- **yt-dlp** — YouTube에서 오디오 추출  
  라이선스: Unlicense  
  https://github.com/yt-dlp/yt-dlp

- **FFmpeg** — 오디오 포맷 변환  
  라이선스: LGPL / GPL  
  외부 명령줄 도구로만 사용됨  
  https://ffmpeg.org/

- **OpenAI Whisper (CLI)** — 음성-텍스트 변환  
  라이선스: MIT  
  https://github.com/openai/whisper

- **Ollama** — 요약을 위한 로컬 LLM 실행기  
  라이선스: Apache 2.0  
  https://ollama.com/

---

## 설치

### 1. 저장소 클론

```bash
git clone https://github.com/gay00ung/yt-whisper-ollama.git
cd yt-whisper-ollama
```

---

### 2. 스크립트를 실행 가능하게 만들기 (중요)

환경에 따라 클론 시 `chmod +x`가 **자동으로 작동하지 않을 수** 있습니다.

실행이 실패하면 **다음 중 하나**를 실행하세요:

```bash
chmod +x yt_whisper.sh
```

그래도 작동하지 않으면:

```bash
bash yt_whisper.sh
```

(`bash`를 직접 사용하면 실행 권한 문제를 우회합니다.)

---

## 사용법

스크립트 실행:

```bash
./yt_whisper.sh
```

또는 실행 권한이 차단된 경우:

```bash
bash yt_whisper.sh
```

다음 항목을 입력하라는 메시지가 표시됩니다:

1. **YouTube URL**
2. **Whisper 모델 크기**

   * `tiny` (39M, ~10배 빠름, ~1GB RAM)
   * `base` (74M, ~7배 빠름, ~1GB RAM)
   * `small` (244M, ~4배 빠름, ~2GB RAM) — **권장**
   * `medium` (769M, ~2배 빠름, ~5GB RAM)
   * `large` (1550M, 1배 속도, ~10GB RAM)
   * `turbo` (가장 빠름, 좋은 품질)
3. **언어** (`ko`, `en`, 또는 `auto`)
4. **Ollama 모델** (기본값: `llama3.1`)
5. **출력 디렉토리** (기본값: `~/Desktop`)

---

## 스크립트 동작 과정

1. 누락된 도구가 있으면 설치:

   * Homebrew
   * yt-dlp
   * ffmpeg
   * openai-whisper
   * ollama
2. Ollama 서버가 실행 중이 아니면 시작
3. YouTube 오디오를 MP3로 다운로드
4. Whisper로 오디오 변환
5. Ollama를 사용하여 트랜스크립트 요약
6. 결과를 선택한 디렉토리의 타임스탬프가 포함된 폴더에 저장

---

## 출력

선택한 디렉토리(기본값: Desktop)에 새 폴더가 생성됩니다:

```
yt_whisper_YYYYMMDD_HHMMSS/
├── video_title.mp3
├── video_title.txt
└── summary.txt
```

* `*.txt` → 전체 트랜스크립션
* `summary.txt` → 요약된 결과

---

## 라이선스

이 프로젝트는 **MIT 라이선스** 하에 배포됩니다.
자세한 내용은 `LICENSE` 파일을 참조하세요.

참고: 이 스크립트가 사용하는 타사 도구는 각각의 라이선스에 따릅니다.

---

## 면책조항

이 스크립트는 개인적, 교육적, 연구 목적으로 사용하도록 제작되었습니다.
사용자는 YouTube 서비스 약관 및 관련 저작권법을 준수할 책임이 있습니다.

---

## 왜 로컬인가?

* API 비용 없음
* 외부 서버로 데이터 전송 없음
* 설정 후 오프라인 작동
* 긴 강연, 강의, 기술 콘텐츠에 이상적
