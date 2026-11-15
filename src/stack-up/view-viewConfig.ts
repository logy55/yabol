// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports, navy palette.
// Stack Up view 튜닝 수치. 길이는 별도 표기가 없으면 "블록 높이(blockH)" 또는 비율.

export const VIEW_CONFIG = {
  /** devicePixelRatio 상한. */
  maxDpr: 2,
  /** 플레이 영역 최대 가로세로비 (폭/높이). 넓은 화면에서는 가운데 세로 띠만 쓴다. */
  maxAspect: 9 / 16,
  /** 블록 높이 = 플레이 폭 * 이 비율 (시안 22/270). */
  blockHeightRatio: 22 / 270,
  /** 베이스 블록 윗면 y = 화면 높이 - blockH * 이 값 (시안 70/22). */
  baseOffsetBlocks: 70 / 22,
  /** 카메라가 따라가기 시작하는 이동 블록 높이 (화면 높이 대비, 위에서부터). */
  followTopRatio: 0.45,
  /** 카메라 보간 속도 (1/초). */
  cameraRate: 5,

  /** 블록 세로 여백 (시안 2/22). 셀 안쪽으로 들어간 만큼 그린다. */
  blockInset: 2 / 22,
  /** 외곽선 두께 (blockH 비율, 시안 1.5/22). */
  strokeWidth: 1.5 / 22,
  /** 글로우 번짐 (blockH 비율). */
  glowBlur: 0.45,
  /** 스프라이트 바깥 여백 (blockH 비율). 글로우가 잘리지 않을 만큼. */
  glowPad: 0.7,
  /** 9-slice 모서리 안쪽 폭 (blockH 비율). */
  capInner: 0.6,

  fillAlpha: 0.16,
  pieceAlpha: 0.75,

  /** 외곽선을 글로우 색보다 얼마나 밝게(흰색 혼합 비율) 할지. */
  strokeLighten: 0.4,

  /** 조각 중력 (blockH/s^2, 시안 900px/22px). */
  pieceGravity: 900 / 22,
  /** 조각 풀 크기. 가득 차면 가장 많이 떨어진 조각을 재사용. */
  piecePoolSize: 24,
  /** 조각 회전 속도 (rad/s): 자르기 1~3 (방향은 side), 완전 빗나감 ±1.5. */
  pieceSpinMin: 1,
  pieceSpinRange: 2,
  dropSpin: 3,

  bgTop: '#112034',
  bgBottom: '#233e5c',

  gridColor: 'rgb(92,191,203)', // #FF3CC8
  /** 그리드 기본 알파 (시안 25%)와 깜박임 폭(0이면 고정), 속도(rad/s). */
  gridAlpha: 0.25,
  gridFlickerDepth: 0.4,
  gridFlickerSpeed: 1.6,
  gridFlickerDepthReduced: 0.12,
  gridHorizontalLines: 8,
  gridCurve: 1.8,
  /** 소실점 쪽/바닥 쪽 세로선 간격 (플레이 폭 비율, 시안 14/270, 60/270). */
  gridSpacingTop: 14 / 270,
  gridSpacingBottom: 60 / 270,

  // --- 별 배경 (뒤에서 앞 순서). drift: 화면 높이/초, parallax: 카메라 1블록 상승당 이동(블록 높이 대비 비율) ---
  stars: [
    { count: 36, drift: 0.006, parallax: 0.06, size: 1, alpha: 0.35, color: '#B58CFF' },
    { count: 24, drift: 0.012, parallax: 0.16, size: 1.5, alpha: 0.5, color: '#8FE8FF' },
    { count: 12, drift: 0.022, parallax: 0.34, size: 2, alpha: 0.7, color: '#FFFFFF' },
  ],
  starSeed: 20240611,
  /** reduced motion에서 별 흐름 속도 배율. */
  starFlowReduced: 0.15,

  // --- VFX (풀 크기는 고정) ---
  particlePoolSize: 96,
  ringPoolSize: 6,
  flashPoolSize: 8,
  /** 안착 외곽선 플래시: 지속(초), 바깥으로 퍼지는 거리(blockH). */
  flashDuration: 0.28,
  flashSpread: 0.3,
  flashLineWidth: 2,
  /** 폭 회복 연출 지속(초). 흰색 외곽선이 이전 폭에서 새 폭으로 늘어난다. */
  regrowDuration: 0.5,
  regrowParticles: 10,
  /** Perfect 사각형 파동: 지속(초), 선 굵기(px, 시작 -> 끝에서 lineEnd 배). */
  ringDuration: 0.6,
  ringLineWidth: 3,
  ringLineEnd: 0.3,
  ringAlpha: 0.9,
  /** 한쪽 가로 확장량(플레이 폭 비율) = 블록 폭 * (base + combo * perCombo), 상한 max (플레이 폭 비율). */
  ringGrowBase: 0.45,
  ringGrowPerCombo: 0.04,
  ringGrowMax: 0.7,
  /** 세로 확장 = 가로 확장(px) * 이 값 (blockH 상한 ringGrowYMax). */
  ringGrowYRatio: 0.5,
  ringGrowYMax: 5,
  /** 파동이 화면 가장자리에서 남겨둘 여백(px)과, 블록이 가장자리에 붙어도 보장하는 최소 확장(blockH 비율). */
  ringScreenMargin: 4,
  ringMinGrowBlocks: 0.5,
  /** 파동 모서리 둥글기 (blockH 비율). */
  ringCorner: 0.35,
  /** 콤보가 이 값 이상이면 블록 색 대신 시안으로 그린다. */
  ringCyanCombo: 3,
  ringCyan: '#33E1FF',
  /** Perfect 입자 수 = base + combo * perCombo (상한 max). */
  perfectParticlesBase: 8,
  perfectParticlesPerCombo: 2,
  perfectParticlesMax: 20,
  particleLife: 0.7,
  particleLifeJitter: 0.4,
  /** 입자 속도: 가로(플레이 폭/초), 위쪽(blockH/초). 중력(blockH/초^2, 아래). */
  particleSpeedX: 0.9,
  particleUp: 5,
  particleUpJitter: 5,
  particleGravity: 14,
  /** 입자 한 변 (px). */
  particleSize: 3,
  /** reduced motion: 입자 수 배율, 링 크기 배율. */
  reducedParticleScale: 0.25,
  reducedRingScale: 0.5,
  /** 마일스톤 배경 플래시: 지속(초), 최고 알파, 올라가는 구간 비율, 색 순환(층마다 번갈아). */
  milestoneFlashDuration: 0.6,
  milestoneFlashAlpha: 0.22,
  milestoneFlashRise: 0.12,
  milestoneFlashColors: ['#FF3CC8', '#33E1FF'],
  /** 플래시 사각형이 화면 밖으로 더 나가는 여유(px, 화면 흔들림 대비). */
  milestoneFlashBleed: 32,
  /** reduced motion: 알파 배율, 지속 배율. */
  reducedFlashAlphaScale: 0.4,
  reducedFlashDurScale: 0.6,
  /** 게임 오버 화면 흔들림: 지속(초), 진폭(blockH), 주파수(Hz). */
  shakeDuration: 0.35,
  shakeAmplitude: 0.45,
  shakeFreq: 22,
} as const;

/** 블록 색 순환 (core의 colorIndex % 5). */
export const BLOCK_COLORS = ['#e6ba70', '#7ad5e0', '#a6aff0', '#8cddbf', '#ed9d99'] as const;
