// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
import { DEFAULT_CONFIG, type StackUpConfig } from './core-config';
import type { Rng } from './core-rng';

/** 안착한 블록. x = 왼쪽 끝, w = 폭 (화면 폭 = 1.0). level 0 = 베이스. */
export interface Block {
  x: number;
  w: number;
  level: number;
  colorIndex: number;
}

/** 현재 좌우로 움직이는 블록. level = 이 블록이 놓일 층. */
export interface MovingBlock {
  x: number;
  w: number;
  dir: 1 | -1;
  speed: number;
  level: number;
  colorIndex: number;
}

export type StackUpEvent =
  | { type: 'land'; level: number; x: number; w: number; perfect: boolean; combo: number }
  | { type: 'perfect'; level: number; combo: number }
  /** 잘린 조각. side: 조각이 블록의 어느 쪽인지. */
  | { type: 'cut'; level: number; x: number; w: number; side: 'left' | 'right'; colorIndex: number }
  /** 폭 회복 (Perfect N연속). amount는 실제 늘어난 폭 (이미 W0면 0일 수 있다). */
  | { type: 'regrow'; level: number; amount: number; newWidth: number }
  /** 층수 마일스톤 도달. floors = 쌓은 층 수 (게임 오버 이벤트의 floors와 같은 정의). */
  | { type: 'milestone'; level: number; floors: number }
  /** 완전히 빗나감. piece = 통째로 떨어지는 블록. */
  | { type: 'gameOver'; score: number; floors: number; maxCombo: number; level: number; x: number; w: number; colorIndex: number };

export class StackUpLogic {
  readonly blocks: Block[] = [];
  readonly current: MovingBlock = { x: 0, w: 0, dir: 1, speed: 0, level: 1, colorIndex: 0 };
  score = 0;
  combo = 0;
  maxCombo = 0;
  isGameOver = false;

  private readonly events: StackUpEvent[] = [];
  private colorStart = 0;
  private startFromLeft = true;

  constructor(
    private readonly rng: Rng,
    readonly config: StackUpConfig = DEFAULT_CONFIG,
  ) {
    this.reset();
  }

  /** 쌓은 층 수 (베이스 제외). */
  get floors(): number {
    return this.blocks.length - 1;
  }

  get top(): Block {
    return this.blocks[this.blocks.length - 1]!;
  }

  /** 새 게임. rng 상태는 이어서 쓴다. */
  reset(): void {
    const c = this.config;
    this.blocks.length = 0;
    this.events.length = 0;
    this.score = 0;
    this.combo = 0;
    this.maxCombo = 0;
    this.isGameOver = false;
    this.colorStart = Math.floor(this.rng() * c.colorCount);
    this.blocks.push({ x: (1 - c.baseWidth) / 2, w: c.baseWidth, level: 0, colorIndex: this.colorStart });
    this.startFromLeft = this.rng() < 0.5;
    this.spawn(this.sideForNext());
  }

  /** 층(level)에 따른 속도. 화면 폭/초. */
  speedForLevel(level: number): number {
    const c = this.config;
    return Math.min(c.speedStart + (level - 1) * c.speedPerLevel, c.speedMax);
  }

  /** 이동 블록 좌우 한계 (왼쪽 끝 x 기준). */
  minX(): number {
    return -this.current.w * this.config.overshootRatio;
  }
  maxX(): number {
    return 1 - this.current.w * (1 - this.config.overshootRatio);
  }

  update(dt: number): void {
    if (this.isGameOver) return;
    const c = this.current;
    c.x += c.dir * c.speed * dt;
    const lo = this.minX();
    const hi = this.maxX();
    if (c.x < lo) {
      c.x = lo;
      c.dir = 1;
    } else if (c.x > hi) {
      c.x = hi;
      c.dir = -1;
    }
  }

  drop(): void {
    if (this.isGameOver) return;
    const cfg = this.config;
    const cur = this.current;
    const top = this.top;
    const level = cur.level;

    const ovL = Math.max(cur.x, top.x);
    const ovR = Math.min(cur.x + cur.w, top.x + top.w);
    const overlap = ovR - ovL;

    if (overlap <= 0) {
      this.isGameOver = true;
      this.combo = 0;
      this.events.push({
        type: 'gameOver', score: this.score, floors: this.floors, maxCombo: this.maxCombo,
        level, x: cur.x, w: cur.w, colorIndex: cur.colorIndex,
      });
      return;
    }

    const tolerance = Math.max(cur.w * cfg.perfectToleranceRatio, cfg.perfectToleranceMin);
    let x: number;
    let w: number;
    let perfect = false;

    if (Math.abs(cur.x - top.x) <= tolerance) {
      perfect = true;
      this.combo++;
      if (this.combo > this.maxCombo) this.maxCombo = this.combo;
      x = top.x;
      w = cur.w;
      this.score += cfg.pointsPerLevel + Math.min(this.combo, cfg.comboBonusCap);
    } else {
      this.combo = 0;
      x = ovL;
      w = overlap;
      if (cur.x < top.x) {
        this.events.push({ type: 'cut', level, x: cur.x, w: ovL - cur.x, side: 'left', colorIndex: cur.colorIndex });
      } else {
        this.events.push({ type: 'cut', level, x: ovR, w: cur.x + cur.w - ovR, side: 'right', colorIndex: cur.colorIndex });
      }
      this.score += cfg.pointsPerLevel;
    }

    let regrow: StackUpEvent | null = null;
    if (perfect && this.combo % cfg.regrowEveryCombo === 0) {
      const newW = Math.min(cfg.baseWidth, w + cfg.baseWidth * cfg.regrowRatio);
      const amount = newW - w;
      x -= amount / 2; // 중심 기준
      w = newW;
      regrow = { type: 'regrow', level, amount, newWidth: newW };
    }

    this.blocks.push({ x, w, level, colorIndex: cur.colorIndex });
    this.events.push({ type: 'land', level, x, w, perfect, combo: this.combo });
    if (perfect) this.events.push({ type: 'perfect', level, combo: this.combo });
    if (regrow) this.events.push(regrow);
    if (this.isMilestone(this.floors)) this.events.push({ type: 'milestone', level, floors: this.floors });

    this.spawn(this.sideForNext());
  }

  /** 쌓인 이벤트를 순서대로 fn에 넘기고 큐를 비운다. */
  consumeEvents(fn: (e: StackUpEvent) => void): void {
    for (let i = 0; i < this.events.length; i++) fn(this.events[i]!);
    this.events.length = 0;
  }

  /** 첫 마일스톤이거나, 그 이후 간격의 배수인 층. */
  isMilestone(floors: number): boolean {
    const c = this.config;
    return floors === c.milestoneFirst || (floors > c.milestoneFirst && floors % c.milestoneInterval === 0);
  }

  /** 시작 방향은 rng, 이후는 층마다 좌우 번갈아. */
  private sideForNext(): boolean {
    return ((this.blocks.length - 1) % 2 === 0) === this.startFromLeft;
  }

  private spawn(fromLeft: boolean): void {
    const top = this.top;
    const c = this.current;
    const level = top.level + 1;
    c.level = level;
    c.w = top.w;
    c.colorIndex = (this.colorStart + level) % this.config.colorCount;
    c.speed = this.speedForLevel(level);
    c.dir = fromLeft ? 1 : -1;
    c.x = fromLeft ? this.minX() : this.maxX();
  }
}
