// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
// 글로우 블록 스프라이트 캐시.
// 색별로 "기준 폭" 블록(채움 + 외곽선 + 글로우)을 오프스크린 캔버스에 한 번만 그리고,
// 임의 폭은 가로 3분할(9-slice의 가로 버전: 왼쪽 모서리 / 늘리는 가운데 / 오른쪽 모서리)로 늘려 그린다.
// 세로는 blockH 고정이므로 늘리지 않는다. shadowBlur는 build() 안에서만 쓰고 프레임 중에는 쓰지 않는다.
import { BLOCK_STYLES } from './view-palette';
import { VIEW_CONFIG } from './view-viewConfig';

export interface SliceWidths {
  left: number;
  mid: number;
  right: number;
}

/** 디바이스 px 정수 폭 w를 모서리(capInner) 두 개와 가운데로 나눈다. 좁은 블록은 좌우 반씩. */
export function sliceWidths(w: number, capInner: number, out: SliceWidths): SliceWidths {
  const left = Math.min(capInner, w >> 1);
  const right = Math.min(capInner, w - left);
  out.left = left;
  out.right = right;
  out.mid = w - left - right;
  return out;
}

type Surface = HTMLCanvasElement | OffscreenCanvas;

export class GlowSprites {
  private sheets: Surface[] = [];
  private s = 1; // dpr
  private pad = 0; // 디바이스 px
  private cap = 0; // 모서리 안쪽 폭, 디바이스 px
  private refInner = 0; // 기준 블록 폭, 디바이스 px
  private cellH = 0; // blockH, 디바이스 px
  private spriteW = 0;
  private builtKey = '';
  private readonly slices: SliceWidths = { left: 0, mid: 0, right: 0 };

  constructor(
    private readonly createSurface: (w: number, h: number) => Surface = (w, h) => {
      const c = document.createElement('canvas');
      c.width = w;
      c.height = h;
      return c;
    },
  ) {}

  /** blockH 또는 dpr이 바뀔 때만 다시 그린다 (리사이즈 시). */
  build(blockH: number, dpr: number): void {
    const key = `${blockH.toFixed(3)}@${dpr}`;
    if (key === this.builtKey) return;
    this.builtKey = key;
    const s = dpr;
    this.s = s;
    const px = (v: number): number => Math.max(1, Math.round(v * s));
    this.pad = px(blockH * VIEW_CONFIG.glowPad);
    this.cap = px(blockH * VIEW_CONFIG.capInner);
    this.cellH = px(blockH);
    this.refInner = this.cap * 2 + this.cellH; // 가운데 늘어나는 구간 = blockH
    this.spriteW = this.refInner + this.pad * 2;
    const spriteH = this.cellH + this.pad * 2;
    const inset = Math.round(blockH * VIEW_CONFIG.blockInset * s);
    const lw = Math.max(1, blockH * VIEW_CONFIG.strokeWidth * s);

    this.sheets = BLOCK_STYLES.map((st) => {
      const surface = this.createSurface(this.spriteW, spriteH);
      const g = surface.getContext('2d') as CanvasRenderingContext2D | OffscreenCanvasRenderingContext2D;
      const x = this.pad;
      const y = this.pad + inset;
      const w = this.refInner;
      const h = this.cellH - inset * 2;
      g.fillStyle = st.fill;
      g.fillRect(x, y, w, h);
      g.shadowColor = st.glow;
      g.shadowBlur = blockH * VIEW_CONFIG.glowBlur * s; // shadowBlur는 변환 영향을 받지 않으므로 디바이스 px
      g.strokeStyle = st.stroke;
      g.lineWidth = lw;
      g.strokeRect(x + lw / 2, y + lw / 2, w - lw, h - lw);
      return surface;
    });
  }

  /**
   * 블록 셀의 왼쪽 위 (x, y), 폭 w (모두 CSS px)에 그린다. 높이는 blockH 고정.
   * 가장자리는 디바이스 px에 맞춰 반올림해 이음새가 보이지 않게 한다.
   */
  draw(ctx: CanvasRenderingContext2D, colorIndex: number, x: number, y: number, w: number): void {
    const sheet = this.sheets[((colorIndex % this.sheets.length) + this.sheets.length) % this.sheets.length];
    if (!sheet) return;
    const s = this.s;
    const x0 = Math.round(x * s);
    const wd = Math.round((x + w) * s) - x0;
    if (wd <= 0) return;
    const sl = sliceWidths(wd, this.cap, this.slices);
    const pad = this.pad;
    const sh = this.cellH + pad * 2;
    const dy = y - pad / s;
    const inv = 1 / s;

    // 왼쪽 (바깥 여백 + 모서리 안쪽)
    ctx.drawImage(sheet, 0, 0, pad + sl.left, sh, (x0 - pad) * inv, dy, (pad + sl.left) * inv, sh * inv);
    // 가운데 (늘림)
    if (sl.mid > 0) {
      ctx.drawImage(sheet, pad + this.cap, 0, this.refInner - this.cap * 2, sh, (x0 + sl.left) * inv, dy, sl.mid * inv, sh * inv);
    }
    // 오른쪽
    ctx.drawImage(
      sheet, this.spriteW - pad - sl.right, 0, pad + sl.right, sh,
      (x0 + wd - sl.right) * inv, dy, (pad + sl.right) * inv, sh * inv,
    );
  }
}
