// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
// 렌더 순서 레이어. StackUpRenderer.addLayer()로 4번(별 배경, VFX 등)이 끼워 넣는다.
import type { StackUpLogic } from './core-StackUpLogic';
import type { GlowSprites } from './view-glowSprites';
import { levelToY, worldToScreenW, worldToScreenX, type Layout } from './view-layout';
import type { Effects } from './view-effects';
import { gridFlickerAlpha } from './view-effects';
import type { PiecePool } from './view-pieces';
import { pieceY } from './view-pieces';
import { VIEW_CONFIG } from './view-viewConfig';

/** 그리는 순서. 숫자 사이에 끼워 넣을 수 있게 간격을 둔다. */
export const RenderPhase = {
  Background: 0, // 그라디언트 (별은 fxLayers.STARS_PHASE = 10)
  Grid: 100,
  Blocks: 200,
  Pieces: 300,
  Effects: 400, // 외곽선 플래시, 링, 입자 (fxLayers.EffectsLayer)
  Overlay: 500, // (6번) HUD 등
} as const;

/** 매 프레임 같은 객체를 재사용한다 (레이어는 저장하지 말고 읽기만). */
export interface FrameContext {
  ctx: CanvasRenderingContext2D;
  layout: Layout;
  logic: StackUpLogic;
  sprites: GlowSprites;
  pieces: PiecePool;
  effects: Effects;
  /** prefers-reduced-motion. */
  reducedMotion: boolean;
  /** 카메라 높이 (층 단위). */
  cam: number;
  /** 누적 시간 (초). */
  time: number;
}

export interface RenderLayer {
  readonly phase: number;
  update?(dt: number, frame: FrameContext): void;
  draw(frame: FrameContext): void;
  onResize?(layout: Layout): void;
}

export class BackgroundLayer implements RenderLayer {
  readonly phase = RenderPhase.Background;
  private gradient: CanvasGradient | null = null;
  private gradientFor: CanvasRenderingContext2D | null = null;
  private h = 0;

  onResize(layout: Layout): void {
    this.h = layout.cssH;
    this.gradient = null; // 다음 draw에서 새 높이로 다시 만든다.
  }

  draw({ ctx, layout }: FrameContext): void {
    if (!this.gradient || this.gradientFor !== ctx || this.h !== layout.cssH) {
      const g = ctx.createLinearGradient(0, 0, 0, layout.cssH);
      g.addColorStop(0, VIEW_CONFIG.bgTop);
      g.addColorStop(1, VIEW_CONFIG.bgBottom);
      this.gradient = g;
      this.gradientFor = ctx;
      this.h = layout.cssH;
    }
    ctx.fillStyle = this.gradient;
    ctx.fillRect(0, 0, layout.cssW, layout.cssH);
  }
}

/** 바닥 원근 그리드. 카메라가 올라가 바닥선이 화면 아래로 벗어나면 그리지 않는다. */
export class GridLayer implements RenderLayer {
  readonly phase = RenderPhase.Grid;

  draw({ ctx, layout, cam, time, reducedMotion }: FrameContext): void {
    const gy = levelToY(layout, 0, cam) + layout.blockH; // 베이스 블록 바로 아래
    if (gy >= layout.cssH) return;
    const H = layout.cssH;
    const cx = layout.cssW / 2;
    const c = VIEW_CONFIG;
    ctx.strokeStyle = c.gridColor;
    ctx.globalAlpha = gridFlickerAlpha(time, reducedMotion);
    ctx.lineWidth = 1;
    ctx.beginPath();
    const n = c.gridHorizontalLines;
    for (let k = 0; k < n; k++) {
      const y = gy + Math.pow(k / (n - 1), c.gridCurve) * (H - gy);
      ctx.moveTo(0, y);
      ctx.lineTo(layout.cssW, y);
    }
    const top = c.gridSpacingTop * layout.playW;
    const bottom = c.gridSpacingBottom * layout.playW;
    const kmax = Math.ceil(cx / bottom) + 1;
    for (let k = -kmax; k <= kmax; k++) {
      ctx.moveTo(cx + k * top, gy);
      ctx.lineTo(cx + k * bottom, H);
    }
    ctx.stroke();
    ctx.globalAlpha = 1;
  }
}

export class BlocksLayer implements RenderLayer {
  readonly phase = RenderPhase.Blocks;

  draw({ ctx, layout, logic, sprites, cam }: FrameContext): void {
    const blocks = logic.blocks;
    const bh = layout.blockH;
    for (let i = 0; i < blocks.length; i++) {
      const b = blocks[i]!;
      const y = levelToY(layout, b.level, cam);
      if (y > layout.cssH || y < -bh) continue;
      sprites.draw(ctx, b.colorIndex, worldToScreenX(layout, b.x), y, worldToScreenW(layout, b.w));
    }
    if (!logic.isGameOver) {
      const c = logic.current;
      sprites.draw(ctx, c.colorIndex, worldToScreenX(layout, c.x), levelToY(layout, c.level, cam), worldToScreenW(layout, c.w));
    }
  }
}

export class PiecesLayer implements RenderLayer {
  readonly phase = RenderPhase.Pieces;

  draw({ ctx, layout, sprites, pieces, cam }: FrameContext): void {
    const items = pieces.items;
    ctx.globalAlpha = VIEW_CONFIG.pieceAlpha;
    for (let i = 0; i < items.length; i++) {
      const p = items[i]!;
      if (!p.active) continue;
      const w = worldToScreenW(layout, p.w);
      const cx = worldToScreenX(layout, p.x) + w / 2;
      const cy = pieceY(layout, p, cam) + layout.blockH / 2;
      ctx.save();
      ctx.translate(cx, cy);
      ctx.rotate(p.rot);
      sprites.draw(ctx, p.colorIndex, -w / 2, -layout.blockH / 2, w);
      ctx.restore();
    }
    ctx.globalAlpha = 1;
  }
}
