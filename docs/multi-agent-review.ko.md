[English](multi-agent-review.md) | **한국어**

# 다중 에이전트 리뷰 파이프라인

> [README.ko.md](README.ko.md)에서 참조

학습이 끝날 때마다 orchestrator는 7명의 독립 리뷰어가 벌이는 구조화된 토론에 결과를 넘깁니다. 단일 에이전트가 결정하지 않습니다 — 결론은 논쟁에서 나옵니다.

---

## 리뷰어 구성

| ID | 역할 | 담당 관점 |
|---|---|---|
| **A** | 통계 분석가 | Loss curve, overfitting 여부, metric 트렌드 — 수치를 직접 인용 |
| **B** | 알고리즘 전문가 | 모델 설계, 학습 전략, 아키텍처 적절성 |
| **C** | 데이터 전문가 | 데이터 파이프라인, 전처리 품질, 샘플링 전략 |
| **D** | Feasibility Assessor | 악마의 변호인 — 각 제안의 실패 시나리오를 분석하고 리스크를 `[LOW/MEDIUM/HIGH]`로 평가 |
| **E** | 보완자 | A/B/C 논리의 빈틈을 채우고 약한 주장을 보강 |
| **F** | 중재자 | A~E 전체의 합의점과 충돌점을 지형도로 정리 — **판단 없이, 지형도만** |
| **G** | Research Innovator | 관련 논문을 웹 검색하고 근본적으로 다른 접근법을 제안 |

각 리뷰어는 데이터를 직접 받지 않고 **파일 경로만** 전달받습니다 — 실험 파일을 직접 읽고 근거 기반 의견을 작성합니다 (800자 제한).

---

## 진행 흐름

```
[학습 종료]
      │
      ▼
  G: Research Brief  ──── WebSearch ────► reports/research_brief_{N}.md
      │
      ▼
  2라운드 ─── 스텝 1 (병렬): A, B, C  ← G의 brief를 참고 자료로 수신
          └── 스텝 2 (병렬): D, E     ← A/B/C 제안 평가
          └── 스텝 3 (순차): F        ← 토론 지형도 작성
      │
      ▼
  3라운드 (병렬): A, B, C가 D/E/F 의견 반영 후 입장 업데이트
      │
      ▼
  Judge  ──── 파일 전체 열람 ────► DECISION + RATIONALE + NEXT_ACTION
      │
      ▼
  Orchestrator 실행
```

전체 사이클(`G brief → 2라운드 → 3라운드 → Judge`)은 `review_cycles` 파라미터로 N회 반복 가능합니다.

---

## G: Research Innovator

G는 본 토론 이전에 독립적으로 실행됩니다.

**G가 하는 일:**
- 현재 실험의 핵심 병목을 파악
- `WebSearch`로 관련 논문·방법론 검색
- `reports/research_brief_{N}.md` 작성 (1500자 이내):

```markdown
# Research Brief — Experiment {N}
## 현재 핵심 문제
[실험 결과에서 식별된 근본 병목 1-2가지]
## 관련 연구 및 방법론
### 방법론 1: [이름] ([논문/출처 URL])
- 핵심 아이디어: ...
- 우리 문제에의 적용: ...
- 이전 시도와의 차이점: ...
### 방법론 2: ...
## 구현 난이도 및 예상 효과
[각 방법론의 복잡도와 기대 효과 요약]
```

**핵심 규칙:**
- G는 **근본적 변경**을 제안합니다 (loss 함수 교체, 아키텍처 패러다임 전환, 학습 전략 전환) — config 조정이 아님
- G는 자신의 제안을 철회하지 않으며 토론 라운드에 참여하지 않음
- A/B/C는 G의 brief를 참고 자료로 받되, 수용 여부는 독립적으로 판단

---

## 2라운드

**스텝 1 — 병렬:** A, B, C가 각자 독립적인 의견을 작성. G의 research brief를 참고 자료로 활용 가능.

**스텝 2 — 병렬:** A/B/C 결과 이후 D와 E가 실행.
- D는 A/B/C 각 제안에 `[LOW/MEDIUM/HIGH]` 리스크를 부여. `HIGH`인 경우 어떤 조건에서 시도할 가치가 있는지 명시.
- E는 A/B/C 논리의 빈틈을 채우고 약한 주장을 강화.

**스텝 3 — 순차:** F가 A~E 전체를 종합해 지형도를 작성 — 합의점, 충돌점, 미결 사항. F는 입장을 취하지 않음.

---

## 3라운드

A, B, C가 D/E/F 의견을 보고 입장을 업데이트합니다. 입장을 바꿀 경우 이유를 명시해야 합니다. 유지도 가능합니다.

---

## Judge

Judge는 **완전히 새로운 context**에서 실행됩니다 — 토론에 참여하지 않으며 파일 경로만 받습니다:

- `reports/experiment_{N}_detail.md` — 리뷰 토론 전문
- `results/experiment_{N}.json` — 수치 결과
- `cache/metric_cache.jsonl` — epoch별 메트릭
- `reports/research_brief_{N}.md` — G의 brief

**출력:**
```
DECISION: [go / config_modify / algo_modify / abort]
RATIONALE: [판정 근거, 200자 이내]
NEXT_ACTION: [다음 실험 계획 — config/algo_modify 시 구체적 변경 사항 포함]
```

**특별 규칙:**
- A/B/C가 채택하지 않은 G의 제안도 근거가 충분하면 `algo_modify` 판정에 반영 가능
- D가 `HIGH` 리스크로 평가한 제안도 실행 조건이 명확하면 채택 가능
- 리뷰어 간 합의 수준보다 **근거의 질**을 우선

---

## 결정 유형

| 결정 | 의미 |
|---|---|
| `go` | 현재 접근법이 충분히 수렴함 — 루프 종료 |
| `config_modify` | 하이퍼파라미터·config 값 조정, 코드 변경 없음 |
| `algo_modify` | 모델 코드·loss 함수·데이터 파이프라인 수정, 새 git branch 생성 |
| `abort` | 학습 실패 (NaN, 발산) — 그래도 리뷰는 진행됨 |

---

## 수렴 원칙

**`go`는 아래 조건을 모두 만족해야 합니다:**
1. 최근 2회 이상 실험에서 핵심 metric 개선폭이 noise 수준 이하
2. config 수정과 알고리즘 수정을 **모두** 시도한 이후
3. 리뷰어 A~F 과반수가 추가 개선 방안을 제시하지 못하고, G의 brief에도 유망한 대안 없음

> 즉: config 조정만 하고 `go`를 선택하는 것은 허용되지 않습니다. 구조적 개선을 먼저 시도해야 합니다.

**Bold Improvement 원칙:**
config 조정만 2회 이상 반복해도 의미 있는 개선이 없으면 다음 판정은 **반드시** 구조적 변경(`algo_modify`)을 시도해야 합니다. 수렴 선언 전에 더 과감한 변경을 먼저 시도하는 방향으로 편향되어 있습니다.

---

## Circuit Breaker

`circuit_breaker=N` 설정 시 동일 결정 유형이 N회 연속되면 Judge에 `circuit_breaker_context` 플래그가 전달됩니다:

- `config_modify` 연속 패턴 → 근거가 압도적이지 않으면 `algo_modify`로 강권
- `algo_modify` 연속 패턴 → 어떤 가정이 틀렸는지 NEXT_ACTION에 명시, `"사용자 검토 권장"` 문구 포함
