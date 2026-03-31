[English](customization.md) | **한국어**

# 커스터마이징 가이드

> [README.ko.md](README.ko.md)에서 참조

---

## 리뷰어 역할

**파일**: `.claude/prompts/train-review-pipeline.md`

기본 다중 에이전트 리뷰 패널은 7명의 리뷰어(A~G)로 구성됩니다. 각 리뷰어는 실험 결과에 대해 다른 관점을 제공합니다:

| ID | 역할 | 초점 |
|---|---|---|
| A | 통계학자 | Loss 곡선, 오버피팅, 메트릭 추이 |
| B | 알고리즘 전문가 | 모델 설계, 학습 전략, 아키텍처 |
| C | 데이터 전문가 | 데이터 파이프라인, 전처리, 샘플링 |
| D | 타당성 평가자 | 리스크 평가, devil's advocate |
| E | 보완 역할 | 빈틈 채우기, 약한 논거 강화 |
| F | 중재자 | 리뷰어 간 합의/갈등 매핑 |
| G | 연구 혁신가 | 관련 논문 웹 검색, 근본적 접근법 변경 |

**커스터마이즈 시점**: 도메인별 특수한 필요가 있을 때 (예: 엣지 배포를 위한 "하드웨어 효율성" 리뷰어 추가, sim-to-real 프로젝트에서 데이터 전문가를 "시뮬레이션 충실도" 리뷰어로 교체).

파일에서 리뷰어 정의를 직접 수정하세요. 동일한 리뷰 흐름 구조를 유지하면서 역할을 추가, 제거, 수정할 수 있습니다.

---

## Abort 조건

**파일**: `.claude/prompts/train-monitor.md`

기본 abort 트리거:
- **NaN / Inf** loss에서 감지
- **val_loss** 최근 평균 대비 3배 이상 발산

**커스터마이즈 시점**: 노이즈가 많은 학습에서 발산 배수를 조정하거나, 도메인별 abort 조건 추가 (예: "GPU 메모리 90% 초과 시 abort", "FID 점수 300 초과 시 abort").

---

## 수렴 기준

**파일**: `.claude/prompts/train-orchestrator-decisions.md`

기본 수렴 기준: "핵심 메트릭 개선이 노이즈 수준 이하인 실험이 2회 이상 연속 + config와 algorithm 수정 모두 시도됨."

**커스터마이즈 시점**: 메트릭이 본질적으로 노이즈가 많은 경우(예: RL reward) 필요 연속 실험 횟수를 늘리세요. 비용이 큰 실험이라면 기준을 낮춰서 더 빨리 수렴하도록 할 수 있습니다.

---

## 디스커션 모듈 테이블

**파일**: `.claude/commands/save-discussion.md`

`/save-discussion` 명령은 키워드-모듈 매핑 테이블을 사용해 토론 파일을 올바른 디렉토리로 라우팅합니다. 기본값은 placeholder 모듈(`module_a`, `module_b`, `module_c`)로 제공됩니다.

**반드시 커스터마이즈해야 합니다.** 예시 모듈을 실제 연구 모듈과 키워드로 교체하세요:

```markdown
| Module key | Keywords | discussion path | topic log path |
|------------|----------|-----------------|----------------|
| `encoder` | encoder, backbone, feature extraction | `research/topics/encoder/discussion/` | `research/topics/encoder/log.md` |
| `loss` | loss function, contrastive, triplet | `research/topics/loss_design/discussion/` | `research/topics/loss_design/log.md` |
```

`meta` 행(워크플로우/도구 논의용)은 그대로 유지할 수 있습니다.

---

## 권한 모드

**파일**: `.claude/settings.local.json`

`defaultMode` 설정은 Claude Code가 도구 사용 시 권한을 요청하는 방식을 제어합니다.

| 모드 | 동작 | 사용 상황 |
|---|---|---|
| `"default"` | 각 도구 사용 시 확인 요청 | 인터랙티브 개발, 수동 감독 |
| `"bypassPermissions"` | 확인 없이 실행 | 완전 자율 `/train` 루프 |

**권장**: 완전 자율 `/train` 루프를 위해 `"defaultMode": "bypassPermissions"`로 설정하세요. 오케스트레이터가 학습 스크립트 실행, 코드 수정, 브랜치 푸시를 매 단계 수동 승인 없이 수행할 수 있습니다.

**주의**: `bypassPermissions`는 프로젝트 내에서 Claude Code에 무제한 셸 접근 권한을 부여합니다. 파이프라인을 완전히 신뢰할 수 있는 격리된 환경(예: 전용 학습 서버)에서만 활성화하세요. 기본값은 `"default"` 모드입니다.

```json
{
  "permissions": {
    "defaultMode": "bypassPermissions"
  }
}
```
