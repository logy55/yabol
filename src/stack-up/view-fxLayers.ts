// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
// 별 배경 / VFX 레이어. 프레임 중 할당 없음, shadowBlur 없음 (알파 도형만).
import type { FrameContext, RenderLayer } from './view-layers';
import { RenderPhase } from './view-layers';
import { levelToY, worldToScreenW, worldToScreenX } from './view-layout';
import { BLOCK_STYLES } from './view-palette';
import { clampWaveGrow, easeOutCubic, milestoneFlashAlpha, waveProgress } from './view-effects';
import { StarField } from './view-stars';
import { VIEW_CONFIG } from './view-viewConfig';

/** 그라디언트 바로 위, 그리드 아래. */
export const STARS_PHASE = RenderPhase.Background + 10;

export class StarsLayer implements RenderLayer {
  readonly phase = STARS_PHASE;
  readonly field: StarField;

  constructor(rand: () => number) {
    this.field = new StarField(rand);
  }

  update(dt: number, f: FrameContext): void {
    this.field.update(dt, f.reducedMotion ? VIEW_CONFIG.starFlowReduced : 1);
  }

  draw({ ctx, layout, cam }: FrameContext): void {
    const fld = this.field;
    const cfgs = VIEW_CONFIG.stars;
    for (let l = 0; l < fld.layerCount; l++) {
      const cfg = cfgs[l]!;
      ctx.globalAlpha = cfg.alpha;
      ctx.fillStyle = cfg.color;
      const end = fld.starts[l + 1]!;
      for (let i = fld.starts[l]!; i < end; i++) {
        ctx.fillRect(fld.u[i]! * layout.cssW, fld.screenY(i, l, cam, layout.blockH, layout.cssH), cfg.size, cfg.size);
      }
    }
    ctx.globalAlpha = 1;
  }
}

/** 마일스톤 배경 플래시. 블록 아래(그리드 위)에 낮은 알파로 깔아 블록이 가려지지 않는다. */
export const MILESTONE_FLASH_PHASE = RenderPhase.Grid + 50;

export class MilestoneFlashLayer implements RenderLayer {
  readonly phase = MILESTONE_FLASH_PHASE;

  draw({ ctx, layout, effects }: FrameContext): void {
    const m = effects.milestone;
    if (!m.active) return;
    const a = milestoneFlashAlpha(m.t, m.dur, m.peak);
    if (a <= 0) return;
    ctx.globalAlpha = a;
    ctx.fillStyle = VIEW_CONFIG.milestoneFlashColors[m.colorIndex % VIEW_CONFIG.milestoneFlashColors.length]!;
    // 화면 흔들림 오프셋이 있어도 가장자리가 비지 않도록 여유를 둔다.
    const b = VIEW_CONFIG.milestoneFlashBleed;
    ctx.fillRect(-b, -b, layout.cssW + b * 2, layout.cssH + b * 2);
    ctx.globalAlpha = 1;
  }
}

export class EffectsLayer implements RenderLayer {
  readonly phase = RenderPhase.Effects;
  /** roundRect 지원 여부 (구형 Safari 대비, 한 번만 판정). */
  private readonly hasRoundRect =
    typeof CanvasRenderingContext2D !== 'undefined' && typeof CanvasRenderingContext2D.prototype.roundRect === 'function';

  /** roundRect가 없으면 arcTo로 같은 경로를 만든다 (할당 없음). */
  private rectPath(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r0: number): void {
    if (this.hasRoundRect) {
      ctx.roundRect(x, y, w, h, r0);
      return;
    }
    const r = Math.max(0, Math.min(r0, w / 2, h / 2));
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  draw({ ctx, layout, cam, effects }: FrameContext): void {
    const c = VIEW_CONFIG;
    const bh = layout.blockH;

    // 외곽선 플래시 / 폭 회복
    const flashes = effects.flashes;
    for (let i = 0; i < flashes.length; i++) {
      const f = flashes[i]!;
      if (!f.active) continue;
      const p = f.t / f.dur;
      const e = easeOutCubic(p);
      const inset = bh * VIEW_CONFIG.blockInset;
      const y = levelToY(layout, f.level, cam) + inset;
      const h = bh - inset * 2;
      ctx.globalAlpha = 1 - p;
      ctx.lineWidth = c.flashLineWidth;
      if (f.grow > 0) {
        // 이전 폭에서 새 폭으로 늘어나는 흰 외곽선
        const wNow = f.w - f.grow * (1 - e);
        const cx = worldToScreenX(layout, f.x + f.w / 2);
        const sw = worldToScreenW(layout, wNow);
        ctx.strokeStyle = '#FFFFFF';
        ctx.strokeRect(cx - sw / 2, y, sw, h);
      } else {
        const spread = e * bh * c.flashSpread;
        ctx.strokeStyle = BLOCK_STYLES[f.colorIndex % BLOCK_STYLES.length]!.stroke;
        ctx.strokeRect(
          worldToScreenX(layout, f.x) - spread, y - spread, worldToScreenW(layout, f.w) + spread * 2, h + spread * 2,
        );
      }
    }

    // Perfect 사각형 파동: 블록 외곽에서 사방으로 퍼지는 둥근 사각형 선 (알파만, shadowBlur 없음)
    const rings = effects.rings;
    for (let i = 0; i < rings.length; i++) {
      const r = rings[i]!;
      if (!r.active) continue;
      const p = r.t / r.dur;
      const e = waveProgress(r.t, r.dur);
      const bx = worldToScreenX(layout, r.x - r.w / 2);
      const bw = worldToScreenW(layout, r.w);
      const gxMax = clampWaveGrow(
        layout.playW * r.grow * r.scale, bx, bw, layout.cssW, c.ringScreenMargin, bh * c.ringMinGrowBlocks,
      );
      const gx = gxMax * e;
      const gy = Math.min(c.ringGrowYMax * bh, gx * c.ringGrowYRatio);
      const inset = bh * c.blockInset;
      const by = levelToY(layout, r.y, cam) + inset;
      ctx.globalAlpha = (1 - p) * c.ringAlpha;
      ctx.lineWidth = c.ringLineWidth * (1 - p * (1 - c.ringLineEnd));
      ctx.strokeStyle = r.combo >= c.ringCyanCombo ? c.ringCyan : BLOCK_STYLES[r.colorIndex % BLOCK_STYLES.length]!.stroke;
      ctx.beginPath();
      this.rectPath(ctx, bx - gx, by - gy, bw + gx * 2, bh - inset * 2 + gy * 2, bh * c.ringCorner);
      ctx.stroke();
    }

    // 입자
    const ps = effects.particles;
    const size = c.particleSize;
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i]!;
      if (!p.active) continue;
      ctx.globalAlpha = Math.min(1, p.life / p.maxLife);
      ctx.fillStyle = BLOCK_STYLES[p.colorIndex % BLOCK_STYLES.length]!.stroke;
      ctx.fillRect(worldToScreenX(layout, p.x) - size / 2, levelToY(layout, p.y, cam) - size / 2, size, size);
    }
    ctx.globalAlpha = 1;
  }
}
