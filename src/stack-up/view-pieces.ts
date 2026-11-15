// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
// 잘린 조각 풀. DOM 참조 없음. 위치는 core 좌표(x,w 정규화) + 층 + 낙하량(dy, blockH 단위).
import { levelToY, type Layout } from './view-layout';
import { VIEW_CONFIG } from './view-viewConfig';

export interface Piece {
  active: boolean;
  x: number;
  w: number;
  level: number;
  colorIndex: number;
  /** 원래 위치에서 아래로 떨어진 거리 (blockH 단위). */
  dy: number;
  vy: number;
  rot: number;
  vr: number;
}

export function stepPiece(p: Piece, dt: number): void {
  p.vy += VIEW_CONFIG.pieceGravity * dt;
  p.dy += p.vy * dt;
  p.rot += p.vr * dt;
}

/** 조각 윗면 y (CSS px). */
export function pieceY(l: Layout, p: Piece, cam: number): number {
  return levelToY(l, p.level, cam) + p.dy * l.blockH;
}

export function isPieceOffscreen(l: Layout, p: Piece, cam: number): boolean {
  return pieceY(l, p, cam) > l.cssH + l.blockH * 2;
}

export class PiecePool {
  readonly items: Piece[] = [];

  constructor(size: number = VIEW_CONFIG.piecePoolSize) {
    for (let i = 0, n = Math.max(1, size); i < n; i++) {
      this.items.push({ active: false, x: 0, w: 0, level: 0, colorIndex: 0, dy: 0, vy: 0, rot: 0, vr: 0 });
    }
  }

  get activeCount(): number {
    let n = 0;
    for (let i = 0; i < this.items.length; i++) if (this.items[i]!.active) n++;
    return n;
  }

  /** 비어 있는 슬롯을 쓴다. 가득 차면 가장 많이 떨어진 조각을 재사용. */
  spawn(x: number, w: number, level: number, colorIndex: number, vr: number): Piece {
    let slot: Piece | null = null;
    let worst: Piece = this.items[0]!;
    for (let i = 0; i < this.items.length; i++) {
      const p = this.items[i]!;
      if (!p.active) {
        slot = p;
        break;
      }
      if (p.dy > worst.dy) worst = p;
    }
    const p = slot ?? worst;
    p.active = true;
    p.x = x;
    p.w = w;
    p.level = level;
    p.colorIndex = colorIndex;
    p.dy = 0;
    p.vy = 0;
    p.rot = 0;
    p.vr = vr;
    return p;
  }

  update(dt: number, layout: Layout, cam: number): void {
    for (let i = 0; i < this.items.length; i++) {
      const p = this.items[i]!;
      if (!p.active) continue;
      stepPiece(p, dt);
      if (isPieceOffscreen(layout, p, cam)) p.active = false;
    }
  }

  clear(): void {
    for (let i = 0; i < this.items.length; i++) this.items[i]!.active = false;
  }
}
