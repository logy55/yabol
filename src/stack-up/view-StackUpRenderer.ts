// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
import type { StackUpEvent, StackUpLogic } from './core-StackUpLogic';
import { Effects } from './view-effects';
import { GlowSprites } from './view-glowSprites';
import { BackgroundLayer, BlocksLayer, GridLayer, PiecesLayer, RenderPhase, type FrameContext, type RenderLayer } from './view-layers';
import { EffectsLayer, MilestoneFlashLayer, StarsLayer } from './view-fxLayers';
import { cameraTarget, computeLayout, stepCamera } from './view-layout';
import { PiecePool } from './view-pieces';
import { createRng } from './core-rng';
import { VIEW_CONFIG } from './view-viewConfig';

export interface RendererOptions {
  /** 조각 회전 방향/속도 난수. 기본 Math.random. */
  random?: () => number;
  /** prefers-reduced-motion. 흔들림 제거, 입자/별 흐름 축소. setReducedMotion()으로 바꿀 수 있다. */
  reducedMotion?: boolean;
}

/**
 * Canvas 2D 렌더러. 게임 상태는 읽기만 한다.
 * 사용: 매 프레임 logic.consumeEvents(renderer.onEvent) → renderer.update(dt) → renderer.render().
 * 확장: addLayer()로 RenderPhase 기준 위치에 레이어를 끼운다.
 * 레이어 순서: 그라디언트(0) → 별(10) → 그리드(100) → 블록(200) → 조각(300) → VFX(400) → 오버레이(500).
 * 화면 흔들림은 별/그라디언트를 제외한 phase 100 이상 전체에 translate로 적용한다.
 */
export class StackUpRenderer {
  readonly frame: FrameContext;
  private readonly ctx: CanvasRenderingContext2D;
  private readonly sprites = new GlowSprites();
  private readonly pieces = new PiecePool();
  private readonly layers: RenderLayer[] = [];
  private readonly random: () => number;
  private readonly effects: Effects;
  /** onEvent에서 perfect/regrow가 직전 land의 위치를 쓰기 위해 보관 (core는 land → perfect → regrow 순서). */
  private landX = 0;
  private landW = 0;

  constructor(
    private readonly canvas: HTMLCanvasElement,
    private readonly logic: StackUpLogic,
    options: RendererOptions = {},
  ) {
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('Canvas 2D is not available');
    this.ctx = ctx;
    this.random = options.random ?? Math.random;
    this.effects = new Effects(this.random);
    this.effects.reducedMotion = options.reducedMotion ?? false;
    this.frame = {
      ctx,
      layout: computeLayout(canvas.clientWidth, canvas.clientHeight, window.devicePixelRatio),
      logic,
      sprites: this.sprites,
      pieces: this.pieces,
      effects: this.effects,
      reducedMotion: this.effects.reducedMotion,
      cam: 0,
      time: 0,
    };
    this.addLayer(new BackgroundLayer());
    this.addLayer(new StarsLayer(createRng(VIEW_CONFIG.starSeed)));
    this.addLayer(new GridLayer());
    this.addLayer(new MilestoneFlashLayer());
    this.addLayer(new BlocksLayer());
    this.addLayer(new PiecesLayer());
    this.addLayer(new EffectsLayer());
    this.resize();
  }

  /** phase 순으로 정렬해 삽입 (같은 phase면 먼저 추가한 것이 먼저). 프레임 중 정렬 없음. */
  addLayer(layer: RenderLayer): void {
    let i = this.layers.length;
    while (i > 0 && this.layers[i - 1]!.phase > layer.phase) i--;
    this.layers.splice(i, 0, layer);
    layer.onResize?.(this.frame.layout);
  }

  /** 캔버스 크기, dpr, 레이아웃, 글로우 스프라이트를 다시 맞춘다. */
  resize(): void {
    const c = this.canvas;
    const layout = computeLayout(c.clientWidth, c.clientHeight, window.devicePixelRatio);
    this.frame.layout = layout;
    const w = Math.round(layout.cssW * layout.dpr);
    const h = Math.round(layout.cssH * layout.dpr);
    if (c.width !== w) c.width = w;
    if (c.height !== h) c.height = h;
    this.sprites.build(layout.blockH, layout.dpr);
    for (const l of this.layers) l.onResize?.(layout);
  }

  /** 새 게임: 카메라를 맨 아래로 되돌리고 조각을 치운다. */
  reset(): void {
    this.frame.cam = 0;
    this.pieces.clear();
    this.effects.clear();
  }

  setReducedMotion(on: boolean): void {
    this.effects.reducedMotion = on;
    this.frame.reducedMotion = on;
    if (on) this.effects.cancelShake();
  }

  /** core 이벤트 처리. 인자 캡처가 없으므로 그대로 consumeEvents에 넘겨도 된다. */
  readonly onEvent = (e: StackUpEvent): void => {
    if (e.type === 'cut') {
      const dir = e.side === 'left' ? -1 : 1;
      const vr = dir * (VIEW_CONFIG.pieceSpinMin + this.random() * VIEW_CONFIG.pieceSpinRange);
      this.pieces.spawn(e.x, e.w, e.level, e.colorIndex, vr);
    } else if (e.type === 'land') {
      this.landX = e.x;
      this.landW = e.w;
      this.effects.spawnLand(e.x, e.w, e.level, this.colorAt(e.level));
    } else if (e.type === 'perfect') {
      this.effects.spawnPerfect(this.landX, this.landW, e.level, this.colorAt(e.level), e.combo);
    } else if (e.type === 'regrow') {
      this.effects.spawnRegrow(this.landX, this.landW, e.level, e.amount, this.colorAt(e.level));
    } else if (e.type === 'milestone') {
      this.effects.spawnMilestone();
    } else if (e.type === 'gameOver') {
      this.effects.startShake();
      const vr = (this.random() - 0.5) * VIEW_CONFIG.dropSpin;
      this.pieces.spawn(e.x, e.w, e.level, e.colorIndex, vr);
    }
  };

  private colorAt(level: number): number {
    return this.logic.blocks[level]?.colorIndex ?? 0;
  }

  update(dt: number): void {
    const f = this.frame;
    f.time += dt;
    f.cam = stepCamera(f.cam, cameraTarget(this.logic.floors, f.layout.followLevels), dt);
    this.pieces.update(dt, f.layout, f.cam);
    this.effects.update(dt);
    for (let i = 0; i < this.layers.length; i++) this.layers[i]!.update?.(dt, f);
  }

  render(): void {
    const f = this.frame;
    const d = f.layout.dpr;
    this.ctx.setTransform(d, 0, 0, d, 0, 0);
    const sh = this.effects.shake;
    const ox = sh.x * f.layout.blockH * d;
    const oy = sh.y * f.layout.blockH * d;
    let shaken = false;
    for (let i = 0; i < this.layers.length; i++) {
      const l = this.layers[i]!;
      if (!shaken && l.phase >= RenderPhase.Grid) {
        this.ctx.setTransform(d, 0, 0, d, ox, oy);
        shaken = true;
      }
      l.draw(f);
    }
  }
}
