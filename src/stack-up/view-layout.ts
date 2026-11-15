// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
// 순수 계산: 화면 레이아웃, 좌표 변환, 카메라. DOM 참조 없음.
import { VIEW_CONFIG } from './view-viewConfig';

export interface Layout {
  cssW: number;
  cssH: number;
  dpr: number;
  /** 플레이 영역 왼쪽 x / 폭 (CSS px). core의 x=0..1이 여기에 대응. */
  playX: number;
  playW: number;
  blockH: number;
  /** 베이스(level 0) 블록 윗면 y (카메라 0일 때). */
  baseY: number;
  /** 카메라가 움직이기 시작하는 층 수. */
  followLevels: number;
}

export function clampDpr(raw: number): number {
  const d = Number.isFinite(raw) && raw > 0 ? raw : 1;
  return Math.min(d, VIEW_CONFIG.maxDpr);
}

export function computeLayout(cssW: number, cssH: number, rawDpr: number): Layout {
  const w = Math.max(1, cssW);
  const h = Math.max(1, cssH);
  const playW = Math.min(w, h * VIEW_CONFIG.maxAspect);
  const blockH = playW * VIEW_CONFIG.blockHeightRatio;
  const baseY = h - blockH * VIEW_CONFIG.baseOffsetBlocks;
  const followLevels = Math.max(3, Math.round((baseY - h * VIEW_CONFIG.followTopRatio) / blockH));
  return { cssW: w, cssH: h, dpr: clampDpr(rawDpr), playX: (w - playW) / 2, playW, blockH, baseY, followLevels };
}

/** core 정규화 x (0..1) → CSS px. */
export function worldToScreenX(l: Layout, x: number): number {
  return l.playX + x * l.playW;
}

/** 정규화 폭 → CSS px. */
export function worldToScreenW(l: Layout, w: number): number {
  return w * l.playW;
}

/** 층의 윗면 y (CSS px). cam = 카메라 높이(층 단위, 위로 갈수록 +). */
export function levelToY(l: Layout, level: number, cam: number): number {
  return l.baseY - (level - cam) * l.blockH;
}

/** 이동 블록이 놓일 층(= floors + 1)이 followLevels를 넘으면 그만큼 올라간다. */
export function cameraTarget(floors: number, followLevels: number): number {
  return Math.max(0, floors + 1 - followLevels);
}

/** 지수 보간 (시안: cam += (target - cam) * min(1, dt * rate)). */
export function stepCamera(cam: number, target: number, dt: number): number {
  return cam + (target - cam) * Math.min(1, dt * VIEW_CONFIG.cameraRate);
}
