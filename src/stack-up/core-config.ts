// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
// Stack Up 튜닝 수치. 좌표 단위는 모두 "정규화 단위":
//   가로: 화면(플레이 영역) 폭 = 1.0, 왼쪽 끝 = 0
//   세로: 블록 높이를 단위로 쓰는 view 쪽 변환은 view가 책임. core는 층(level) 인덱스만 안다.
//   시간: 초(dt), 속도: 화면 폭/초

export interface StackUpConfig {
  /** 베이스 블록(및 폭 회복 상한) 폭 W0. 화면 폭 대비. */
  readonly baseWidth: number;
  /** Perfect 허용치 = 현재 블록 폭 * 이 비율 (화면 폭 단위 아님, 비율). */
  readonly perfectToleranceRatio: number;
  /** Perfect 허용치 최소 하한 (화면 폭 단위). */
  readonly perfectToleranceMin: number;
  /** Perfect 연속 N회마다 폭 회복. */
  readonly regrowEveryCombo: number;
  /** 폭 회복량 = baseWidth * 이 비율. */
  readonly regrowRatio: number;
  /** 시작 속도 (화면 폭/초). 첫 이동 블록(1층) 기준. */
  readonly speedStart: number;
  /** 층당 속도 증가 (화면 폭/초). */
  readonly speedPerLevel: number;
  /** 속도 상한 (화면 폭/초). */
  readonly speedMax: number;
  /** 층당 기본 점수. */
  readonly pointsPerLevel: number;
  /** Perfect 보너스 콤보 상한. 보너스 = min(콤보, 이 값). */
  readonly comboBonusCap: number;
  /** 이동 블록이 화면 밖으로 나갈 수 있는 비율(블록 폭 대비). 시안: 왼쪽 90%, 오른쪽 90% 까지 */
  readonly overshootRatio: number;
  /** 첫 마일스톤 층수. */
  readonly milestoneFirst: number;
  /** 첫 마일스톤 이후 간격 (층). 층이 간격의 배수일 때 발생. */
  readonly milestoneInterval: number;
  /** 블록 색 팔레트 길이 (색 인덱스 순환용). 실제 색은 view가 정한다. */
  readonly colorCount: number;
}

export const DEFAULT_CONFIG: StackUpConfig = {
  baseWidth: 0.55,
  perfectToleranceRatio: 0.045,
  perfectToleranceMin: 0.006,
  regrowEveryCombo: 5,
  regrowRatio: 0.08,
  speedStart: 0.4,
  speedPerLevel: 0.025,
  speedMax: 1.2,
  pointsPerLevel: 1,
  comboBonusCap: 5,
  overshootRatio: 0.9,
  milestoneFirst: 5,
  milestoneInterval: 10,
  colorCount: 5,
};
