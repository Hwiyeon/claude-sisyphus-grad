[English](../README.md) | **한국어**

# claude-sisyphus-grad

![claude-sisyphus-grad](../imgs/sisyphus-grad.png)

> *"시지프스는 행복하다고 상상해야 한다."* — 알베르 카뮈

"ablation 하나만 더"에 한 번도 눈살 찌푸리지 않고, 새벽 3시 학습도 기꺼이 돌리고, 동료 여섯 명과 결과를 토론하고, 코드까지 고쳐놓고, 연구노트도 꼬박꼬박 쓰는 — 지도교수가 꿈꾸던 그 대학원생. 알고 보니 Claude Code였습니다.

**두 가지 핵심 기능:**
- **실험 자동화** — 자는 동안 실험 → 검토 → 개선 → 반복 루프를 자율적으로 수행
- **연구노트 자동화** — 로그를 구조화하고, 아키텍처 변경 이력을 추적하고, 어떤 실험 흐름이든 몇 초 안에 다시 파악 가능

---

## 빠른 시작

```bash
# 1. 프로젝트에 복사
cp -r .claude scripts CLAUDE.md /your/project/
cp -r research-template /your/project/research

# 2. 설정
edit CLAUDE.md   # CONDA_ENV=your_env_name 설정

# 3. (선택) research/를 별도 git repo로 설정 (자동 동기화용)
cd your-project/research && git init && git remote add origin <your-repo-url>

# 4. 실행
/train script=train.py config=configs/myexp.yaml max_experiments=10 experiment_title="baseline_v1" env=myenv
```

> 전체 설치 가이드 및 파일 구조: [getting-started.ko.md](getting-started.ko.md)

---

## 실험 자동화

**실험 → 검토 → 개선 → 반복** 루프를 자동화합니다:

1. **`/train`** — 백그라운드에서 `scripts/train-loop.sh`를 실행하며, 각 이터레이션마다 새로운 `claude -p` 세션 생성
2. **Orchestrator** — `session_continuation.json`으로 상태 관리, 학습 스크립트 실행 및 메트릭 모니터링
3. **다중 에이전트 리뷰** — 7명의 리뷰어(A~G)가 결과를 토론 → [상세 보기](multi-agent-review.ko.md)
4. **Judge** — 결정: `go` / `config_modify` / `algo_modify` / `abort`
5. **Code Modifier** — `algo_modify` 시 git branch 생성 후 소스 코드 자율 수정, 재시작
6. **루프** — `max_experiments` 도달 또는 수렴 확인까지 반복

루프는 잠든 사이 돌아갑니다. 일어나면 `session_report.md`와 모든 코드 변경사항이 담긴 git branch가 준비되어 있습니다.

### `/train`

자동화된 실험 루프 전체를 실행합니다.

```
/train script=train.py config=configs/myexp.yaml max_experiments=10 experiment_title="baseline_v1" env=myenv
```

`goal`(자연어 목표), `instructions`(초기 힌트), `parallel`(병렬 실행), `subset`(2단계 전략)을 지원합니다.
→ [전체 사용 예시 및 인자 테이블](train-internals.ko.md#사용법)

### `/analyze`

실험 루프 시작 전 사전 분석을 실행합니다. 긴 실험에 투자하기 전에 데이터셋 파악, 베이스라인 동작 확인, config 검증에 유용합니다.

```
/analyze
/analyze target="학습 전 클래스 불균형과 feature 분포 확인"
```

### `/review`

다중 에이전트 리뷰 파이프라인을 독립적으로 실행합니다 — 새 학습 실행 없이. 기존 실험 결과 검토나 추가 의견이 필요할 때 사용합니다.

```
/review
/review run=results/exp_003 focus="왜 epoch 40에서 val loss가 발산했는가?"
```

→ [리뷰 파이프라인 상세](multi-agent-review.ko.md)

---

## 연구노트

구조화된 연구노트 시스템. 모든 실험 실행, 아키텍처 결정, 토론 내용이 조회 가능한 디렉토리에 기록됩니다. "지난주에 뭘 시도했지?" 또는 "현재 아키텍처가 뭔데?"에 항상 몇 초 안에 답할 수 있습니다.

### `/discuss`

연구 컨텍스트(로그, 아키텍처 문서, 실험 이력)를 로드하고 인터랙티브 연구 논의를 시작합니다.

```
/discuss                               # 전체 연구 현황 개요
/discuss attention                     # "attention" 주제 심층 논의
/discuss "왜 val loss가 불안정한가"    # 전체 컨텍스트 기반 자유 질문
```

**예시 세션:**
```
/discuss positional_encoding

> Claude: 실험 로그 기준으로 3가지 변형을 시도했습니다: RoPE (exp_007),
> ALiBi (exp_012), 학습된 절대 위치 인코딩 (exp_003). RoPE가 최고 val
> accuracy (87.3%)를 기록했지만 512 토큰 이상에서 길이 일반화 문제가
> 있었습니다. ALiBi는 아직 전체 데이터셋에서 미검증 상태입니다.
> 길이 일반화 실패 원인을 파고들까요?
```

### `/save-discussion`

현재 논의 내용을 `research/topics/<주제>/discussion/` 하위의 구조화된 파일로 저장합니다.

```
/save-discussion
/save-discussion title="positional encoding 트레이드오프 2026-03-24"
```

### 연구 디렉토리 구조

```
research/
├── CLAUDE.md          ← 운영 규칙
├── README.md          ← 연구 현황 요약
├── logs/YYYY-MM-DD/   ← 일별 인덱스 로그 + 시각화
├── summaries/         ← 주간 요약
├── topics/<주제>/     ← 주제별 로그, 아키텍처 명세, 토론 아카이브
└── related_work/      ← 논문·참고 자료
```

→ [파일별 역할 및 로깅 규칙](research-notes.ko.md) | [로그 작성 가이드](research-log-rules.ko.md)

---

## 커스터마이징

주요 설정 포인트 — [전체 커스터마이징 가이드](customization.ko.md) 참조:

- **리뷰어 역할** — 7명 리뷰어 패널을 도메인에 맞게 조정
- **Abort / 수렴 기준** — 메트릭에 맞게 튜닝
- **디스커션 모듈 테이블** — `/save-discussion`을 실제 연구 모듈에 매핑
- **권한 모드** — 완전 자율 실행을 위한 `bypassPermissions` ([상세](customization.ko.md#권한-모드))

---

## 요구사항

- [Claude Code](https://claude.ai/code) CLI
- `conda` (환경 활성화용)
- `jq` (셸 JSON 파싱)
- `flock` (hook 동기화 락, Linux 기본 제공; macOS는 `brew install util-linux`)
- 선택: `wandb` (메트릭 로깅 — 없으면 stdout 파싱으로 대체)

---

## 참고

이 프로젝트는 활발히 개발 중입니다. 기능 및 API가 예고 없이 변경될 수 있습니다.
