[English](research-notes.md) | **한국어**

# 연구노트 시스템

> [README.ko.md](README.ko.md)에서 참조

연구노트 시스템은 모든 실험 실행, 아키텍처 결정, 논의를 기록하는 구조화된 디렉토리입니다. 목표: 연구의 현재 상태나 이력에 관한 어떤 질문이든 30초 안에 답할 수 있어야 합니다.

---

## 디렉토리 구조

```
research/
├── CLAUDE.md                      ← 운영 규칙 (세션 시작 시 자동 로딩)
├── README.md                      ← 연구 현황 요약 (GitHub 표시용)
├── state.md                       ← 간결한 "현재 상태" 스냅샷 (선택 — /research-state 로 유지)
├── logs/
│   ├── YYYY-MM-DD/
│   │   ├── log.md                 ← 일별 인덱스 + 비토픽 상세 기록
│   │   └── *.png / *.jpg          ← 실험 결과 시각화 (같은 폴더에 저장)
│   └── archive/
│       └── MMDD~MMDD/             ← 주간 아카이브 (매주 수요일 이동)
├── summaries/
│   └── week-MMDD~MMDD.md          ← 주간 요약 (요청 시 생성)
├── topics/
│   └── <주제>/
│       ├── architecture_<주제>.md  ← 현재 best 명세만
│       ├── experiment_log.md       ← 아키텍처 변경 이력 (최신 순)
│       ├── log.md                  ← 주제별 누적 로그
│       └── discussion/             ← 저장된 /discuss 세션
└── related_work/                  ← 관련 논문·기법 정리
```

---

## 파일별 역할과 사용법

### `research/README.md`

연구 현황 라이브 요약본. GitHub에 직접 표시됩니다. 중요한 결정이 내려지거나 연구 방향이 바뀔 때마다 갱신합니다.

포함 내용:
- 현재 연구 방향과 풀고 있는 문제
- 최근 진행 상황 (최근 1–2 세션을 2–3 문장으로)
- 확정된 핵심 결정
- 다음 세션을 이끄는 열린 질문

### `research/state.md` (선택)

`README.md`와는 다른 시점의 뷰인, 간결한(~3~5K tokens) "지금 상태" 스냅샷. `/research-state` 커맨드로 유지합니다.

세 가지 뷰의 차이:
- **`/discuss` 캐시** — 전체 연구 인덱스 (~100K+ tokens), Claude 내부용
- **`README.md`** — history 중심 요약, GitHub에서 사람이 읽는 용도
- **`state.md`** — action 중심 스냅샷, 휴식 후 빠른 재진입과 외부 LLM(ChatGPT, Gemini) 공유 붙여넣기용

구조는 HTML 주석 마커로 빌드 생성 영역과 산문 영역을 분리합니다:

- `<!-- AUTO:... -->` 섹션은 매 `/research-state` 실행 시 재생성: 타임스탬프 헤더, 드리프트 경고 (README와 최근 로그의 mtime 비교), 주요 원본 파일 포인터
- `<!-- MANUAL:... -->` 섹션은 Claude가 제안하고 사용자가 승인한 Edit으로만 갱신: 현재 active focus + decision tree, 모듈별 best 메트릭, 최근 confirmed decisions, 재탐색 방지용 기각된 경로, Top open questions

이 분리 덕분에 AUTO가 쉬운 갱신을 맡아 파일이 항상 최신 상태를 유지하면서도, MANUAL 산문이 silent 덮어쓰기로 뉘앙스를 잃지 않습니다.

동반 `--export` 모드는 포인터 파일들을 하나의 self-contained 번들(`state_standalone.md`, 통상 gitignore 대상)로 인라인해 외부 공유용으로 사용합니다.

### `logs/YYYY-MM-DD/log.md`

일별 인덱스 로그. 각 작업 세션 종료 시 작성합니다.

사용 목적:
- 당일 여러 주제에 걸친 관찰
- 여러 주제에 걸친 결정
- 상세 내용은 토픽 로그를 가리키는 포인터
- 특정 주제에 속하지 않는 실험 결과

**포함하지 않는 것**: 주제별 상세 내용 — 그것은 `topics/<주제>/log.md`에 있습니다.

### `topics/<주제>/log.md`

특정 모듈이나 연구 흐름의 primary 상세 기록. 전체 시도 이력이 여기 있습니다: 시도한 것, 실패한 것, ASCII 다이어그램, 수식, 코드.

형식:
```markdown
# <모듈명> — Progress Log

## YYYY-MM-DD
### 주제 / 요약 한 줄
- 논의 내용, 결정 사항, 실험 결과
- 기각된 아이디어와 사유 (해당 시)
- 관련 메트릭, 수식, 코드 스니펫
```

### `architecture_<주제>.md`

현재 best 명세만. 변경 이력이 아닙니다.

- 갱신 시 **항상 덮어씁니다** — 파일 내에 버전을 누적하지 않음
- 현재 아키텍처, config, 제약 조건만 포함
- 이 파일은 "X의 현재 버전이 무엇인가?"에 답합니다

### `experiment_log.md`

주제의 전체 아키텍처 변경 이력.

구조:
```
## 아키텍처 v3 (YYYY-MM-DD)
[v3 전체 명세]

### 알고리즘 변경: ALiBi 추가 (YYYY-MM-DD)
### Config 조정: lr 1e-3 → 5e-4 (YYYY-MM-DD)
```

헤딩 레벨: `##` 아키텍처 버전 → `###` 알고리즘 변경 → `####` config 튜닝.

### `topics/<주제>/discussion/`

저장된 `/discuss` 세션. 각 파일은 연구 토론 내용의 타임스탬프가 붙은 마크다운 파일입니다. 같은 주제의 이후 `/discuss` 세션에서 자동으로 참조됩니다.

### `summaries/week-MMDD~MMDD.md`

`weekly-summary` 스킬이 생성합니다. 해당 주의 실험, 결정, 열린 질문에 대한 구조화된 요약을 포함합니다. 요청 시 생성("주간 요약", "이번주 정리", "weekly summary"). 생성 후 해당 일별 폴더들은 `logs/archive/`로 이동됩니다.

### `related_work/`

논문, 기법, 외부 참조 자료. 고정 형식 없음 — 주로 주제별 또는 처음 접한 날짜 순으로 정리.

---

## 2단계 로깅 실전 가이드

이 시스템은 **일별 인덱스** (오늘 주제들에 걸쳐 일어난 일)와 **토픽 primary 기록** (특정 모듈의 권위 있는 상세 기록)을 분리합니다.

**일별 로그에 쓸 때:**
- 여러 주제에 걸친 관찰이나 결정
- 상세 내용 없이 어떤 일이 있었는지 기록할 때 (토픽 로그를 가리키는 포인터와 함께)
- 세션 레벨 요약

**토픽 로그에 쓸 때:**
- 특정 모듈의 시행착오 상세 이력
- 주제의 아키텍처 다이어그램이나 수식
- 현재 접근법에 대한 권위 있는 기록

**규칙:** 판단이 어려울 때는 토픽 로그에 쓰고 일별 로그에 한 줄 포인터를 남기세요. 상세 내용을 두 곳 모두에 중복으로 쓰지 마세요.

---

## Skills

| Skill | 트리거 | 동작 |
|---|---|---|
| `research-log` | orchestrator 및 `/discuss`에서 참조 | 로그 템플릿, 디렉토리 구조, 동기화 규칙 |
| `weekly-summary` | "주간 요약", "이번주 정리", "weekly summary" | 주간 로그 읽기 → `summaries/week-*.md` 생성 → 일별 폴더 아카이브 이동 |

---

## GitHub 자동 동기화

파이프라인에는 PostToolUse hook이 포함되어 있어, Claude가 `research/` 내 파일을 쓰거나 수정할 때마다 자동으로 GitHub에 push합니다 — 수동 커밋이 필요 없습니다.

### 동작 방식

`sync-research-log.sh`는 모든 `Write`와 `Edit` 도구 호출 시 실행됩니다. 수정된 파일 경로에 `/research/`가 포함되어 있으면 백그라운드에서 실행됩니다:

```bash
git pull --rebase origin main   # 충돌 방지를 위해 먼저 pull
git add -A
git commit -m "research log sync: YYYY-MM-DD HH:MM"
git push origin main
```

`flock`으로 연속적인 파일 쓰기 시 동시 sync를 방지합니다. 백그라운드 실행이라 Claude의 응답을 차단하지 않습니다.

### 전제 조건: `research/`가 별도 git repo여야 함

Hook은 `research/`가 `origin` 리모트를 가진 독립 git repository라고 가정합니다. 그렇지 않으면 hook이 조용히 종료됩니다 (오류 없음).

**셋업:**
```bash
cd your-project/research
git init
git remote add origin https://github.com/your-user/your-research-repo.git
git push -u origin main
```

또는 기존 repo를 직접 clone:
```bash
git clone https://github.com/your-user/your-research-repo.git research
```

### `research/`가 별도 repo가 아닌 경우

모든 것을 하나의 repo에 유지하고 싶다면, hook은 실행되지 않습니다 (경로 체크가 `/research/`를 필요로 하고, 해당 디렉토리에 자체 git remote가 없으므로). 이 경우 로그는 일반 git 워크플로우로 메인 repo에 커밋됩니다.

### 커스텀 동기화 커맨드

기본 동기화 동작을 오버라이드하려면 `CLAUDE.md`에 `RESEARCH_SYNC_CMD`를 설정하세요:

```bash
RESEARCH_SYNC_CMD="bash scripts/my_sync.sh"
```

### Hook 등록

Hook은 `.claude/settings.local.json`에 등록되어 있습니다:

```json
"PostToolUse": [
  { "matcher": "Write", "hooks": [{ "type": "command", "command": ".claude/hooks/sync-research-log.sh" }] },
  { "matcher": "Edit",  "hooks": [{ "type": "command", "command": ".claude/hooks/sync-research-log.sh" }] }
]
```

참고: `settings.local.json`은 기본적으로 git에 커밋되지 않습니다. 이 파이프라인을 새 프로젝트에 복사할 때는 자신의 `settings.local.json`에 hook을 다시 등록해야 합니다.

---

## 작성 규칙

로그를 *어떻게* 작성할지 (무엇을 포함할지, 섹션별 규칙, 생략하면 안 되는 것)에 대한 상세 가이드는 [research-log-rules.ko.md](research-log-rules.ko.md)를 참조하세요.
