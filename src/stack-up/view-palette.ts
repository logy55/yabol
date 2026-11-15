// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
import { BLOCK_COLORS, VIEW_CONFIG } from './view-viewConfig';

function parse(hex: string): [number, number, number] {
  const n = parseInt(hex.slice(1), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

export interface BlockStyle {
  fill: string;
  stroke: string;
  glow: string;
}

/** 시작 시 한 번만 계산하는 색 문자열 (프레임 중 문자열 생성 방지). */
export const BLOCK_STYLES: readonly BlockStyle[] = BLOCK_COLORS.map((hex) => {
  const [r, g, b] = parse(hex);
  const k = VIEW_CONFIG.strokeLighten;
  const lr = Math.round(r + (255 - r) * k);
  const lg = Math.round(g + (255 - g) * k);
  const lb = Math.round(b + (255 - b) * k);
  return {
    fill: `rgba(${r},${g},${b},${VIEW_CONFIG.fillAlpha})`,
    stroke: `rgb(${lr},${lg},${lb})`,
    glow: hex,
  };
});
