// Copyright 2026 DevCol. Apache-2.0. Modified for YABOL: flattened imports.
// 패럴랙스 별 필드. 순수 계산 (DOM 없음). 고정 크기 배열만 쓰고 프레임 중 할당하지 않는다.
import { VIEW_CONFIG } from './view-viewConfig';

/** 0..1 범위로 래핑 (음수 포함). */
export function wrap01(v: number): number {
  return v - Math.floor(v);
}

export class StarField {
  readonly layerCount = VIEW_CONFIG.stars.length;
  /** 레이어별 시작 인덱스 (길이 layerCount + 1). */
  readonly starts: Int32Array;
  readonly u: Float32Array;
  readonly v: Float32Array;
  /** 레이어별 누적 흐름량 (화면 높이 비율). */
  readonly scroll: Float64Array;

  constructor(rand: () => number) {
    this.starts = new Int32Array(this.layerCount + 1);
    let total = 0;
    for (let l = 0; l < this.layerCount; l++) {
      this.starts[l] = total;
      total += VIEW_CONFIG.stars[l]!.count;
    }
    this.starts[this.layerCount] = total;
    this.u = new Float32Array(total);
    this.v = new Float32Array(total);
    this.scroll = new Float64Array(this.layerCount);
    for (let i = 0; i < total; i++) {
      this.u[i] = rand();
      this.v[i] = rand();
    }
  }

  /** flowScale: 1 = 기본 흐름, 0 = 정지. */
  update(dt: number, flowScale: number): void {
    for (let l = 0; l < this.layerCount; l++) {
      this.scroll[l] = wrap01(this.scroll[l]! + dt * VIEW_CONFIG.stars[l]!.drift * flowScale);
    }
  }

  /** 별 i(레이어 l)의 화면 y (CSS px). 카메라가 올라가면 별은 아래로 내려간다 (깊을수록 적게). */
  screenY(i: number, l: number, cam: number, blockH: number, cssH: number): number {
    const par = VIEW_CONFIG.stars[l]!.parallax;
    return wrap01(this.v[i]! + this.scroll[l]! + (cam * par * blockH) / cssH) * cssH;
  }
}
