[English](getting-started.md) | **한국어**

# 시작하기

> [README.ko.md](README.ko.md)에서 참조

---

## 사전 요구사항

- [Claude Code](https://claude.ai/code) CLI
- `conda` (환경 활성화용)
- `jq` (셸 JSON 파싱)
- `flock` (hook 동기화 락, Linux 기본 제공; macOS는 `brew install util-linux`)
- 선택: `wandb` (메트릭 로깅 — 없으면 stdout 파싱으로 대체)

---

## Step 1. 프로젝트에 복사

```bash
cp -r /path/to/claude-sisyphus-grad/.claude /your/project/
cp -r /path/to/claude-sisyphus-grad/scripts /your/project/
cp /path/to/claude-sisyphus-grad/CLAUDE.md /your/project/   # 이후 수정
cp -r /path/to/claude-sisyphus-grad/research-template /your/project/research
```

또는 clone 후 `.claude/`를 프로젝트에 symlink로 연결.

---

## Step 2. `research/`를 별도 git repo로 설정 (선택, 권장)

파이프라인에는 Claude가 `research/`에 파일을 쓸 때마다 자동으로 GitHub에 commit & push하는 PostToolUse hook이 포함되어 있습니다. 이를 위해 `research/`가 별도 repo여야 합니다:

```bash
cd your-project/research
git init && git remote add origin https://github.com/your-user/your-research-repo.git
git push -u origin main
```

또는 기존 repo를 `research/`로 직접 clone. 이 단계를 건너뛰면 자동 동기화는 조용히 비활성화되고 로그는 메인 repo에 정상적으로 커밋됩니다.

> [자동 동기화 상세 및 hook 등록 방법](research-notes.ko.md#github-자동-동기화)

---

## Step 3. CLAUDE.md 설정

프로젝트 루트의 `CLAUDE.md` 수정:

```
CONDA_ENV=your_env_name
```

메트릭 수집, 동기화 커맨드 등 선택적 설정 (자세한 내용은 `CLAUDE.md` 참조).

---

## Step 4. 실행

```
/train script=train.py config=configs/myexp.yaml max_experiments=10 experiment_title="baseline_v1" env=myenv
```

---

## Step 5. 프로젝트에 맞게 커스터마이즈

파이프라인이 당신의 연구를 이해하려면 아래 항목들을 적용해야 합니다.

### 디스커션 토픽 모듈 — 필수

**파일**: `.claude/commands/save-discussion.md`

`/save-discussion` 명령은 키워드 매칭으로 토론 파일을 올바른 디렉토리에 저장합니다. placeholder 모듈을 실제 연구 토픽으로 교체하세요:

```markdown
| Module key  | Keywords                                | discussion path                               | topic log path                         |
|-------------|-----------------------------------------|-----------------------------------------------|----------------------------------------|
| `module_a`  | keyword1, keyword2, keyword3            | `research/topics/module_a/discussion/`        | `research/topics/module_a/log.md`      |
| `module_b`  | keyword4, keyword5, keyword6            | `research/topics/module_b/discussion/`        | `research/topics/module_b/log.md`      |
| `module_c`  | keyword7, keyword8                      | `research/topics/module_c/discussion/`        | `research/topics/module_c/log.md`      |
| `meta`      | research system, logging, workflow, Claude Code | `research/topics/analysis/discussion/` | (none)                                 |
```

`meta` 행은 워크플로우/도구 관련 토론용으로 유지하세요. 나머지는 프로젝트의 모듈 구조에 맞게 교체합니다.

### 연구노트 템플릿 — 필수

`research-template/`를 `research/`로 복사한 후, 두 파일을 수정하세요:

**`research/README.md`** — placeholder 토픽 테이블을 실제 연구 현황으로 교체:
```markdown
## Current Research Status

| Topic    | Status | Recent Progress       |
|----------|--------|-----------------------|
| module_a | Active | ...                   |
| module_b | On hold | ...                  |
```

**`research/CLAUDE.md`** — Claude의 연구노트 작성 규칙. 모듈 참조(예: `topics/<topic>/`)를 위의 `save-discussion` 테이블의 모듈 키와 일치하는 실제 토픽 디렉토리 이름으로 업데이트하세요.

### 권한 모드 — 자율 실행 시 권장

**파일**: `.claude/settings.local.json`

`/train` 오케스트레이터가 각 단계에서 수동 승인 없이 실행되게 하려면:
```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```

> 활성화 전에 [커스터마이징 가이드의 주의사항](customization.ko.md#권한-모드)을 확인하세요.

### 리뷰어 역할 — 선택

**파일**: `.claude/prompts/train-review-pipeline.md`

7명 리뷰어 패널을 도메인에 맞게 조정. [커스터마이징 가이드](customization.ko.md#리뷰어-역할) 참조.

### Abort / 수렴 조건 — 선택

**파일**: `.claude/prompts/train-monitor.md`, `.claude/prompts/train-orchestrator-decisions.md`

메트릭 노이즈 수준에 맞게 조정. [커스터마이징 가이드](customization.ko.md#abort-조건) 참조.

---

## 파일 구조

```
.claude/
  commands/
    train.md              # /train 런처
    review.md             # /review 독립 실행
    analyze.md            # /analyze 사전 분석
    discuss.md            # /discuss 연구 컨텍스트 로더
    save-discussion.md    # /save-discussion  ← 모듈 테이블 커스터마이즈
  prompts/
    train-orchestrator.md          # 메인 orchestrator 로직
    train-orchestrator-decisions.md # Strict Convergence + Bold Improvement 원칙
    train-monitor.md               # 메트릭 폴링 + epoch 단위 리뷰
    train-review-pipeline.md       # 다중 에이전트 리뷰 (A~G + Judge)  ← 리뷰어 커스터마이즈
    train-recording-rules.md       # 로깅 포맷 + 서기 규칙
    train-code-modifier.md         # 자율 코드 수정 절차
    discuss-system.md              # discuss 모드 행동 규칙
  hooks/
    sync-research-log.sh   # PostToolUse hook: 파일 쓰기 시 research/ 자동 동기화
  skills/
    research-log/SKILL.md  # 로그 템플릿 + 디렉토리 구조
    weekly-summary/SKILL.md # 주간 요약 생성 규칙
  settings.local.json      # 권한 allowlist + hook 등록  ← defaultMode 설정
scripts/
  train-loop.sh            # 외부 루프 래퍼 (이터레이션마다 claude -p 생성)
research-template/
  CLAUDE.md                # 템플릿: research/CLAUDE.md로 복사  ← 토픽 이름 커스터마이즈
  README.md                # 템플릿: research/README.md로 복사  ← 연구 현황 업데이트
docs/
  getting-started.ko.md    # 이 파일
  customization.ko.md      # 커스터마이징 가이드
  multi-agent-review.ko.md # 다중 에이전트 리뷰 파이프라인 상세
  train-internals.ko.md    # /train 루프 동작 + 상태 파일 + 실험 파일 구조
  research-notes.ko.md     # 연구 디렉토리 구조 + 파일별 역할
  research-log-rules.ko.md # 로그 작성 철학과 섹션별 규칙
```
