[English](train-internals.md) | **한국어**

# `/train` 내부 동작

> [README.ko.md](README.ko.md)에서 참조

---

## 사용법

### 기본 사용
```
/train script=train.py config=configs/myexp.yaml max_experiments=10 experiment_title="baseline_v1" env=myenv
```

### 목표와 힌트 포함
```
/train script=train.py config=configs/exp.yaml max_experiments=15 experiment_title="attention_ablation" env=myenv \
  goal="파라미터 50M 이하로 유지하면서 val accuracy 92% 이상 달성" \
  instructions="아키텍처 건드리기 전에 learning rate schedule 변형부터 테스트"
```

### 병렬 실행 (예: 하이퍼파라미터 스윕)
```
/train script=train.py config=configs/sweep.yaml max_experiments=20 experiment_title="lr_sweep" env=myenv parallel=3
```

### 2단계 전략 (빠른 subset 먼저, 이후 full data)
```
/train script=train.py config=configs/exp.yaml max_experiments=10 experiment_title="subset_trial" env=myenv subset=true
```

### 인자

| 인자 | 설명 | 기본값 |
|---|---|---|
| `script` | 학습 스크립트 경로 | 필수 |
| `config` | 설정 파일 경로 | 필수 |
| `max_experiments` | 최대 반복 횟수 | 필수 |
| `experiment_title` | 세션 이름 (디렉토리/브랜치 명에 사용) | 필수 |
| `env` | Conda 환경 이름 | 필수 |
| `parallel` | 병렬 실행 수 | `1` |
| `subset` | subset→full 2단계 전략 사용 여부 | `false` |
| `goal` | "좋은 결과"의 기준 (자연어) | — |
| `instructions` | orchestrator에게 전달할 초기 힌트 | — |
| `circuit_breaker` | 동일 유형 결정 N회 연속 시 알림 | — |

---

## 루프 동작 방식

```
사용자가 /train 실행
      │
      ▼
scripts/train-loop.sh  ──── 이터레이션마다 claude -p 생성 ────┐
      │                                                          │
      │  ┌──────────────────────────────────────────────────────┘
      │  │  Claude 세션 (orchestrator)
      │  │    session_continuation.json 읽기
      │  │    ├─ status=initial       → 디렉토리 초기화, 학습 실행
      │  │    ├─ status=analyzed      → 사전 분석 생략, 학습 실행
      │  │    └─ status=pending_resume → next_action 적용 후 학습 실행
      │  │
      │  │  학습 실행
      │  │    stdout / wandb에서 메트릭 모니터링
      │  │    epoch별 metric_cache.jsonl 기록
      │  │    NaN / loss 발산 감지 시 abort
      │  │
      │  │  다중 에이전트 리뷰
      │  │    G research brief (WebSearch) → 2라운드 → 3라운드 → Judge
      │  │
      │  │  next_action과 함께 session_continuation.json 저장
      │  │  session_report.md 업데이트
      │  │  종료 (이터레이션 마커 출력)
      │  │
      └──┴─ train-loop.sh가 마커를 읽고 다음 세션 생성
```

각 Claude 세션은 무상태(stateless)입니다 — 모든 상태는 `session_continuation.json`과 `research/logs/` 하위 실험 파일에 영속됩니다.

---

## 상태 파일: `session_continuation.json`

이터레이션 간 orchestrator의 영속 상태. 각 세션 종료 시 쓰이고, 다음 세션 시작 시 읽힙니다.

```json
{
  "session": {
    "script": "train.py",
    "config": "configs/exp.yaml",
    "env": "myenv",
    "goal": "val_acc 92% 이상 달성",
    "max_experiments": 10,
    "review_cycles": 1,
    "parallel": 1,
    "subset": false,
    "experiment_title": "baseline_v1",
    "instructions": null,
    "circuit_breaker": null
  },
  "status": "initial | analyzed | pending_resume | completed | stopped",
  "progress": {
    "next_experiment_n": 3,
    "next_run_name": "exp3_algo_mod",
    "decision_history": ["go", "config_modify", "algo_modify"],
    "current_git_branch": "train/baseline_v1/exp2-code-mod",
    "subset_phase": null
  },
  "next_action": {
    "type": "config_modify | algo_modify | subset_to_full",
    "config_changes": [
      { "key": "optimizer.lr", "value": 0.0005, "reason": "epoch 12 이후 정체" }
    ],
    "algo_changes": "encoder block 3–6에 residual connection 추가"
  },
  "handoff_summary": {
    "last_judge_rationale": "val_loss 정체 + 리뷰어 B가 skip connection 누락 지적",
    "key_hypothesis": "residual connection이 깊은 레이어의 gradient flow를 안정화할 것",
    "failed_approaches": ["lr warmup", "dropout 0.3으로 증가"],
    "best_metric_so_far": { "val_acc": 0.873, "experiment_n": 1 }
  }
}
```

### Status 값

| Status | 의미 |
|---|---|
| `initial` | 첫 이터레이션; orchestrator가 디렉토리를 초기화하고 실험 1을 시작 |
| `analyzed` | 사전 분석(`/analyze`) 완료; 실험 1 시작 준비됨 |
| `pending_resume` | 이전 이터레이션 완료; `next_action` 실행 대기 중 |
| `completed` | 루프가 정상 종료 (`go` 결정 또는 `max_experiments` 도달) |
| `stopped` | 사용자가 중단하거나 복구 불가 오류 발생 |

---

## `algo_modify` 시 동작

Judge가 `algo_modify`를 결정하면:

1. Orchestrator가 `.claude/prompts/train-orchestrator-decisions.md`를 읽어 코드 수정 절차를 따름
2. 새 git branch 생성: `train/{experiment_title}/exp{N}-code-mod`
3. Code Modifier 에이전트가 리뷰 기록을 읽고 소스 코드를 자율적으로 수정 (사용자 확인 없이)
4. 수정 범위: 모델 아키텍처, loss 함수, 데이터 파이프라인
5. branch가 push됨; `session_continuation.json`에 branch 이름 기록
6. 다음 이터레이션은 수정된 코드로 학습 실행

세션 종료 후 어떤 branch든 `git diff`, `git log`, `git revert`로 검토·롤백할 수 있습니다.

---

## 메트릭 수집

Orchestrator는 두 가지 소스에서 학습 중 메트릭을 모니터링합니다 (우선순위 순):

1. **wandb** — 사용 가능한 경우 wandb API로 step별 메트릭 조회
2. **stdout 파싱** — wandb 없으면 `epoch={N} loss={x} val_loss={x}` 패턴으로 학습 스크립트 stdout 파싱

메트릭은 epoch별로 `cache/metric_cache.jsonl`에 기록됩니다. abort 조건(NaN, loss 3배 발산)은 실시간으로 체크됩니다.

커스텀 메트릭 패턴은 `CLAUDE.md`의 `METRIC_FETCH_CMD` 또는 `EPOCH_LOG_PATTERN`으로 설정할 수 있습니다.

---

## 실험 파일 구조

각 실험은 `research/logs/YYYY-MM-DD/{experiment_title}/` 하위에 기록됩니다:

```
results/
  experiment_{N}.json          ← 최종 메트릭 + config 스냅샷
  experiment_{N}_aborted.json  ← abort 발생 시 대신 생성
reports/
  session_report.md            ← 세션 누적 로그 (전체 실험)
  experiment_{N}_detail.md     ← 상세 기록: 학습 로그 + 리뷰 전문
  research_brief_{N}.md        ← G의 웹 검색 결과
  pre_analysis_briefing.md     ← /analyze 사용 시 briefing 에이전트가 생성
cache/
  metric_cache.jsonl           ← epoch별 메트릭 (JSONL)
  metric_last_step.txt         ← 마지막 조회 step (증분 폴링용)
```
