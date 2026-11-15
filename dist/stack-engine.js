/*! Stack Up — Copyright 2026 DevCol, Apache-2.0. Modified for YABOL. See stack-NOTICE.txt and stack-LICENSE.txt. */

// work/yabol-deploy/src/stack-up/core-config.ts
var DEFAULT_CONFIG = {
  baseWidth: 0.55,
  perfectToleranceRatio: 0.045,
  perfectToleranceMin: 6e-3,
  regrowEveryCombo: 5,
  regrowRatio: 0.08,
  speedStart: 0.4,
  speedPerLevel: 0.025,
  speedMax: 1.2,
  pointsPerLevel: 1,
  comboBonusCap: 5,
  overshootRatio: 0.9,
  milestoneFirst: 5,
  milestoneInterval: 10,
  colorCount: 5
};

// work/yabol-deploy/src/stack-up/core-StackUpLogic.ts
var StackUpLogic = class {
  constructor(rng, config = DEFAULT_CONFIG) {
    this.rng = rng;
    this.config = config;
    this.reset();
  }
  rng;
  config;
  blocks = [];
  current = { x: 0, w: 0, dir: 1, speed: 0, level: 1, colorIndex: 0 };
  score = 0;
  combo = 0;
  maxCombo = 0;
  isGameOver = false;
  events = [];
  colorStart = 0;
  startFromLeft = true;
  /** 쌓은 층 수 (베이스 제외). */
  get floors() {
    return this.blocks.length - 1;
  }
  get top() {
    return this.blocks[this.blocks.length - 1];
  }
  /** 새 게임. rng 상태는 이어서 쓴다. */
  reset() {
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
  speedForLevel(level) {
    const c = this.config;
    return Math.min(c.speedStart + (level - 1) * c.speedPerLevel, c.speedMax);
  }
  /** 이동 블록 좌우 한계 (왼쪽 끝 x 기준). */
  minX() {
    return -this.current.w * this.config.overshootRatio;
  }
  maxX() {
    return 1 - this.current.w * (1 - this.config.overshootRatio);
  }
  update(dt) {
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
  drop() {
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
        type: "gameOver",
        score: this.score,
        floors: this.floors,
        maxCombo: this.maxCombo,
        level,
        x: cur.x,
        w: cur.w,
        colorIndex: cur.colorIndex
      });
      return;
    }
    const tolerance = Math.max(cur.w * cfg.perfectToleranceRatio, cfg.perfectToleranceMin);
    let x;
    let w;
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
        this.events.push({ type: "cut", level, x: cur.x, w: ovL - cur.x, side: "left", colorIndex: cur.colorIndex });
      } else {
        this.events.push({ type: "cut", level, x: ovR, w: cur.x + cur.w - ovR, side: "right", colorIndex: cur.colorIndex });
      }
      this.score += cfg.pointsPerLevel;
    }
    let regrow = null;
    if (perfect && this.combo % cfg.regrowEveryCombo === 0) {
      const newW = Math.min(cfg.baseWidth, w + cfg.baseWidth * cfg.regrowRatio);
      const amount = newW - w;
      x -= amount / 2;
      w = newW;
      regrow = { type: "regrow", level, amount, newWidth: newW };
    }
    this.blocks.push({ x, w, level, colorIndex: cur.colorIndex });
    this.events.push({ type: "land", level, x, w, perfect, combo: this.combo });
    if (perfect) this.events.push({ type: "perfect", level, combo: this.combo });
    if (regrow) this.events.push(regrow);
    if (this.isMilestone(this.floors)) this.events.push({ type: "milestone", level, floors: this.floors });
    this.spawn(this.sideForNext());
  }
  /** 쌓인 이벤트를 순서대로 fn에 넘기고 큐를 비운다. */
  consumeEvents(fn) {
    for (let i = 0; i < this.events.length; i++) fn(this.events[i]);
    this.events.length = 0;
  }
  /** 첫 마일스톤이거나, 그 이후 간격의 배수인 층. */
  isMilestone(floors) {
    const c = this.config;
    return floors === c.milestoneFirst || floors > c.milestoneFirst && floors % c.milestoneInterval === 0;
  }
  /** 시작 방향은 rng, 이후는 층마다 좌우 번갈아. */
  sideForNext() {
    return (this.blocks.length - 1) % 2 === 0 === this.startFromLeft;
  }
  spawn(fromLeft) {
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
};

// work/yabol-deploy/src/stack-up/core-rng.ts
function createRng(seed) {
  let a = seed >>> 0;
  return () => {
    a = a + 1831565813 >>> 0;
    let t = a;
    t = Math.imul(t ^ t >>> 15, t | 1);
    t ^= t + Math.imul(t ^ t >>> 7, t | 61);
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

// work/yabol-deploy/src/stack-up/view-viewConfig.ts
var VIEW_CONFIG = {
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
  bgTop: "#112034",
  bgBottom: "#233e5c",
  gridColor: "rgb(92,191,203)",
  // #FF3CC8
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
    { count: 36, drift: 6e-3, parallax: 0.06, size: 1, alpha: 0.35, color: "#B58CFF" },
    { count: 24, drift: 0.012, parallax: 0.16, size: 1.5, alpha: 0.5, color: "#8FE8FF" },
    { count: 12, drift: 0.022, parallax: 0.34, size: 2, alpha: 0.7, color: "#FFFFFF" }
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
  ringCyan: "#33E1FF",
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
  milestoneFlashColors: ["#FF3CC8", "#33E1FF"],
  /** 플래시 사각형이 화면 밖으로 더 나가는 여유(px, 화면 흔들림 대비). */
  milestoneFlashBleed: 32,
  /** reduced motion: 알파 배율, 지속 배율. */
  reducedFlashAlphaScale: 0.4,
  reducedFlashDurScale: 0.6,
  /** 게임 오버 화면 흔들림: 지속(초), 진폭(blockH), 주파수(Hz). */
  shakeDuration: 0.35,
  shakeAmplitude: 0.45,
  shakeFreq: 22
};
var BLOCK_COLORS = ["#e6ba70", "#7ad5e0", "#a6aff0", "#8cddbf", "#ed9d99"];

// work/yabol-deploy/src/stack-up/view-effects.ts
function easeOutCubic(t) {
  const k = 1 - t;
  return 1 - k * k * k;
}
function waveMaxGrow(w, combo) {
  const c = VIEW_CONFIG;
  return Math.min(c.ringGrowMax, w * (c.ringGrowBase + Math.max(0, combo) * c.ringGrowPerCombo));
}
function clampWaveGrow(desired, blockLeft, blockW, screenW, margin, minGrow) {
  const room = Math.min(blockLeft, screenW - (blockLeft + blockW)) - margin;
  return Math.min(desired, Math.max(minGrow, room));
}
function waveProgress(t, dur) {
  return easeOutCubic(Math.min(1, Math.max(0, t / dur)));
}
function milestoneFlashAlpha(t, dur, peak) {
  if (dur <= 0 || t < 0 || t >= dur) return 0;
  const p = t / dur;
  const rise = VIEW_CONFIG.milestoneFlashRise;
  if (p < rise) return peak * (p / rise);
  const k = (1 - p) / (1 - rise);
  return peak * k * k;
}
function shakeOffset(elapsed, duration, amp, freq, phase) {
  if (duration <= 0 || elapsed >= duration || elapsed < 0) return 0;
  const k = 1 - elapsed / duration;
  return amp * k * k * Math.sin(elapsed * freq * Math.PI * 2 + phase);
}
function acquire(items, age) {
  let worst = items[0];
  let worstAge = -Infinity;
  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    if (!it.active) return it;
    const a = age(it);
    if (a > worstAge) {
      worstAge = a;
      worst = it;
    }
  }
  return worst;
}
var particleAge = (p) => p.maxLife - p.life;
var ringAge = (r) => r.t / r.dur;
var flashAge = (f) => f.t / f.dur;
function countActive(items) {
  let n = 0;
  for (let i = 0; i < items.length; i++) if (items[i].active) n++;
  return n;
}
var Effects = class {
  constructor(random = Math.random) {
    this.random = random;
    const c = VIEW_CONFIG;
    for (let i = 0; i < Math.max(1, c.particlePoolSize); i++) {
      this.particles.push({ active: false, x: 0, y: 0, vx: 0, vy: 0, life: 0, maxLife: 1, colorIndex: 0 });
    }
    for (let i = 0; i < Math.max(1, c.ringPoolSize); i++) {
      this.rings.push({ active: false, x: 0, y: 0, w: 0, grow: 0, combo: 0, t: 0, dur: 1, scale: 1, colorIndex: 0 });
    }
    for (let i = 0; i < Math.max(1, c.flashPoolSize); i++) {
      this.flashes.push({ active: false, x: 0, w: 0, level: 0, t: 0, dur: 1, grow: 0, colorIndex: 0 });
    }
  }
  random;
  particles = [];
  rings = [];
  flashes = [];
  milestone = { active: false, t: 0, dur: 1, peak: 0, colorIndex: 0 };
  milestoneCount = 0;
  shake = { elapsed: 0, duration: 0, amp: 0, x: 0, y: 0 };
  /** true면 흔들림 없음, 입자/링 축소. */
  reducedMotion = false;
  get activeParticles() {
    return countActive(this.particles);
  }
  get activeRings() {
    return countActive(this.rings);
  }
  get activeFlashes() {
    return countActive(this.flashes);
  }
  /** 블록 안착: 외곽선 플래시. */
  spawnLand(x, w, level, colorIndex) {
    const f = acquire(this.flashes, flashAge);
    f.active = true;
    f.x = x;
    f.w = w;
    f.level = level;
    f.t = 0;
    f.dur = VIEW_CONFIG.flashDuration;
    f.grow = 0;
    f.colorIndex = colorIndex;
  }
  /** Perfect: 링 파동 + 윗면에서 튀는 입자. combo가 클수록 입자 증가. */
  spawnPerfect(x, w, level, colorIndex, combo) {
    const c = VIEW_CONFIG;
    const r = acquire(this.rings, ringAge);
    r.active = true;
    r.x = x + w / 2;
    r.y = level;
    r.w = w;
    r.grow = waveMaxGrow(w, combo);
    r.combo = combo;
    r.t = 0;
    r.dur = c.ringDuration;
    r.scale = this.reducedMotion ? c.reducedRingScale : 1;
    r.colorIndex = colorIndex;
    const base = Math.min(c.perfectParticlesMax, c.perfectParticlesBase + combo * c.perfectParticlesPerCombo);
    this.burst(x, w, level, colorIndex, this.scaled(base));
  }
  /** 콤보 5 단위 폭 회복. amount <= 0이면 아무것도 하지 않는다. */
  spawnRegrow(x, w, level, amount, colorIndex) {
    if (!(amount > 0)) return;
    const f = acquire(this.flashes, flashAge);
    f.active = true;
    f.x = x;
    f.w = w;
    f.level = level;
    f.t = 0;
    f.dur = VIEW_CONFIG.regrowDuration;
    f.grow = amount;
    f.colorIndex = colorIndex;
    const n = this.scaled(VIEW_CONFIG.regrowParticles);
    for (let i = 0; i < n; i++) {
      const left = (i & 1) === 0;
      const p = this.newParticle(left ? x : x + w, level - 0.5, colorIndex);
      p.vx = (left ? -1 : 1) * (0.2 + this.random() * VIEW_CONFIG.particleSpeedX * 0.6);
    }
  }
  /** 마일스톤: 배경 색 플래시. 층마다 색을 번갈아 쓴다. reduced motion이면 약하고 짧게. */
  spawnMilestone() {
    const c = VIEW_CONFIG;
    const m = this.milestone;
    m.active = true;
    m.t = 0;
    m.dur = c.milestoneFlashDuration * (this.reducedMotion ? c.reducedFlashDurScale : 1);
    m.peak = c.milestoneFlashAlpha * (this.reducedMotion ? c.reducedFlashAlphaScale : 1);
    m.colorIndex = this.milestoneCount++ % c.milestoneFlashColors.length;
  }
  /** 게임 오버 흔들림. reduced motion이면 무시. */
  startShake() {
    if (this.reducedMotion) return;
    const s = this.shake;
    s.elapsed = 0;
    s.duration = VIEW_CONFIG.shakeDuration;
    s.amp = VIEW_CONFIG.shakeAmplitude;
  }
  cancelShake() {
    const s = this.shake;
    s.elapsed = 0;
    s.duration = 0;
    s.x = 0;
    s.y = 0;
  }
  update(dt) {
    const c = VIEW_CONFIG;
    for (let i = 0; i < this.particles.length; i++) {
      const p = this.particles[i];
      if (!p.active) continue;
      p.life -= dt;
      if (p.life <= 0) {
        p.active = false;
        continue;
      }
      p.vy -= c.particleGravity * dt;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
    }
    for (let i = 0; i < this.rings.length; i++) {
      const r = this.rings[i];
      if (!r.active) continue;
      r.t += dt;
      if (r.t >= r.dur) r.active = false;
    }
    for (let i = 0; i < this.flashes.length; i++) {
      const f = this.flashes[i];
      if (!f.active) continue;
      f.t += dt;
      if (f.t >= f.dur) f.active = false;
    }
    const m = this.milestone;
    if (m.active) {
      m.t += dt;
      if (m.t >= m.dur) m.active = false;
    }
    const s = this.shake;
    if (s.elapsed < s.duration) {
      s.elapsed += dt;
      s.x = shakeOffset(s.elapsed, s.duration, s.amp, c.shakeFreq, 0);
      s.y = shakeOffset(s.elapsed, s.duration, s.amp, c.shakeFreq * 1.3, 1.7);
    } else {
      s.x = 0;
      s.y = 0;
    }
  }
  clear() {
    for (let i = 0; i < this.particles.length; i++) this.particles[i].active = false;
    for (let i = 0; i < this.rings.length; i++) this.rings[i].active = false;
    for (let i = 0; i < this.flashes.length; i++) this.flashes[i].active = false;
    this.milestone.active = false;
    this.milestoneCount = 0;
    const s = this.shake;
    s.elapsed = 0;
    s.duration = 0;
    s.x = 0;
    s.y = 0;
  }
  scaled(n) {
    if (!this.reducedMotion) return n;
    return Math.max(2, Math.round(n * VIEW_CONFIG.reducedParticleScale));
  }
  burst(x, w, level, colorIndex, n) {
    const c = VIEW_CONFIG;
    for (let i = 0; i < n; i++) {
      const p = this.newParticle(x + this.random() * w, level, colorIndex);
      p.vx = (this.random() - 0.5) * 2 * c.particleSpeedX;
    }
  }
  newParticle(x, y, colorIndex) {
    const c = VIEW_CONFIG;
    const p = acquire(this.particles, particleAge);
    p.active = true;
    p.x = x;
    p.y = y;
    p.vx = 0;
    p.vy = c.particleUp + this.random() * c.particleUpJitter;
    p.maxLife = c.particleLife + this.random() * c.particleLifeJitter;
    p.life = p.maxLife;
    p.colorIndex = colorIndex;
    return p;
  }
};
function gridFlickerAlpha(time, reducedMotion) {
  const c = VIEW_CONFIG;
  const depth = reducedMotion ? c.gridFlickerDepthReduced : c.gridFlickerDepth;
  const wave = 0.5 + 0.5 * Math.sin(time * c.gridFlickerSpeed);
  return c.gridAlpha * (1 - depth + depth * wave);
}

// work/yabol-deploy/src/stack-up/view-palette.ts
function parse(hex) {
  const n = parseInt(hex.slice(1), 16);
  return [n >> 16 & 255, n >> 8 & 255, n & 255];
}
var BLOCK_STYLES = BLOCK_COLORS.map((hex) => {
  const [r, g, b] = parse(hex);
  const k = VIEW_CONFIG.strokeLighten;
  const lr = Math.round(r + (255 - r) * k);
  const lg = Math.round(g + (255 - g) * k);
  const lb = Math.round(b + (255 - b) * k);
  return {
    fill: `rgba(${r},${g},${b},${VIEW_CONFIG.fillAlpha})`,
    stroke: `rgb(${lr},${lg},${lb})`,
    glow: hex
  };
});

// work/yabol-deploy/src/stack-up/view-glowSprites.ts
function sliceWidths(w, capInner, out) {
  const left = Math.min(capInner, w >> 1);
  const right = Math.min(capInner, w - left);
  out.left = left;
  out.right = right;
  out.mid = w - left - right;
  return out;
}
var GlowSprites = class {
  constructor(createSurface = (w, h) => {
    const c = document.createElement("canvas");
    c.width = w;
    c.height = h;
    return c;
  }) {
    this.createSurface = createSurface;
  }
  createSurface;
  sheets = [];
  s = 1;
  // dpr
  pad = 0;
  // 디바이스 px
  cap = 0;
  // 모서리 안쪽 폭, 디바이스 px
  refInner = 0;
  // 기준 블록 폭, 디바이스 px
  cellH = 0;
  // blockH, 디바이스 px
  spriteW = 0;
  builtKey = "";
  slices = { left: 0, mid: 0, right: 0 };
  /** blockH 또는 dpr이 바뀔 때만 다시 그린다 (리사이즈 시). */
  build(blockH, dpr) {
    const key = `${blockH.toFixed(3)}@${dpr}`;
    if (key === this.builtKey) return;
    this.builtKey = key;
    const s = dpr;
    this.s = s;
    const px = (v) => Math.max(1, Math.round(v * s));
    this.pad = px(blockH * VIEW_CONFIG.glowPad);
    this.cap = px(blockH * VIEW_CONFIG.capInner);
    this.cellH = px(blockH);
    this.refInner = this.cap * 2 + this.cellH;
    this.spriteW = this.refInner + this.pad * 2;
    const spriteH = this.cellH + this.pad * 2;
    const inset = Math.round(blockH * VIEW_CONFIG.blockInset * s);
    const lw = Math.max(1, blockH * VIEW_CONFIG.strokeWidth * s);
    this.sheets = BLOCK_STYLES.map((st) => {
      const surface = this.createSurface(this.spriteW, spriteH);
      const g = surface.getContext("2d");
      const x = this.pad;
      const y = this.pad + inset;
      const w = this.refInner;
      const h = this.cellH - inset * 2;
      g.fillStyle = st.fill;
      g.fillRect(x, y, w, h);
      g.shadowColor = st.glow;
      g.shadowBlur = blockH * VIEW_CONFIG.glowBlur * s;
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
  draw(ctx, colorIndex, x, y, w) {
    const sheet = this.sheets[(colorIndex % this.sheets.length + this.sheets.length) % this.sheets.length];
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
    ctx.drawImage(sheet, 0, 0, pad + sl.left, sh, (x0 - pad) * inv, dy, (pad + sl.left) * inv, sh * inv);
    if (sl.mid > 0) {
      ctx.drawImage(sheet, pad + this.cap, 0, this.refInner - this.cap * 2, sh, (x0 + sl.left) * inv, dy, sl.mid * inv, sh * inv);
    }
    ctx.drawImage(
      sheet,
      this.spriteW - pad - sl.right,
      0,
      pad + sl.right,
      sh,
      (x0 + wd - sl.right) * inv,
      dy,
      (pad + sl.right) * inv,
      sh * inv
    );
  }
};

// work/yabol-deploy/src/stack-up/view-layout.ts
function clampDpr(raw) {
  const d = Number.isFinite(raw) && raw > 0 ? raw : 1;
  return Math.min(d, VIEW_CONFIG.maxDpr);
}
function computeLayout(cssW, cssH, rawDpr) {
  const w = Math.max(1, cssW);
  const h = Math.max(1, cssH);
  const playW = Math.min(w, h * VIEW_CONFIG.maxAspect);
  const blockH = playW * VIEW_CONFIG.blockHeightRatio;
  const baseY = h - blockH * VIEW_CONFIG.baseOffsetBlocks;
  const followLevels = Math.max(3, Math.round((baseY - h * VIEW_CONFIG.followTopRatio) / blockH));
  return { cssW: w, cssH: h, dpr: clampDpr(rawDpr), playX: (w - playW) / 2, playW, blockH, baseY, followLevels };
}
function worldToScreenX(l, x) {
  return l.playX + x * l.playW;
}
function worldToScreenW(l, w) {
  return w * l.playW;
}
function levelToY(l, level, cam) {
  return l.baseY - (level - cam) * l.blockH;
}
function cameraTarget(floors, followLevels) {
  return Math.max(0, floors + 1 - followLevels);
}
function stepCamera(cam, target, dt) {
  return cam + (target - cam) * Math.min(1, dt * VIEW_CONFIG.cameraRate);
}

// work/yabol-deploy/src/stack-up/view-pieces.ts
function stepPiece(p, dt) {
  p.vy += VIEW_CONFIG.pieceGravity * dt;
  p.dy += p.vy * dt;
  p.rot += p.vr * dt;
}
function pieceY(l, p, cam) {
  return levelToY(l, p.level, cam) + p.dy * l.blockH;
}
function isPieceOffscreen(l, p, cam) {
  return pieceY(l, p, cam) > l.cssH + l.blockH * 2;
}
var PiecePool = class {
  items = [];
  constructor(size = VIEW_CONFIG.piecePoolSize) {
    for (let i = 0, n = Math.max(1, size); i < n; i++) {
      this.items.push({ active: false, x: 0, w: 0, level: 0, colorIndex: 0, dy: 0, vy: 0, rot: 0, vr: 0 });
    }
  }
  get activeCount() {
    let n = 0;
    for (let i = 0; i < this.items.length; i++) if (this.items[i].active) n++;
    return n;
  }
  /** 비어 있는 슬롯을 쓴다. 가득 차면 가장 많이 떨어진 조각을 재사용. */
  spawn(x, w, level, colorIndex, vr) {
    let slot = null;
    let worst = this.items[0];
    for (let i = 0; i < this.items.length; i++) {
      const p2 = this.items[i];
      if (!p2.active) {
        slot = p2;
        break;
      }
      if (p2.dy > worst.dy) worst = p2;
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
  update(dt, layout, cam) {
    for (let i = 0; i < this.items.length; i++) {
      const p = this.items[i];
      if (!p.active) continue;
      stepPiece(p, dt);
      if (isPieceOffscreen(layout, p, cam)) p.active = false;
    }
  }
  clear() {
    for (let i = 0; i < this.items.length; i++) this.items[i].active = false;
  }
};

// work/yabol-deploy/src/stack-up/view-layers.ts
var RenderPhase = {
  Background: 0,
  // 그라디언트 (별은 fxLayers.STARS_PHASE = 10)
  Grid: 100,
  Blocks: 200,
  Pieces: 300,
  Effects: 400,
  // 외곽선 플래시, 링, 입자 (fxLayers.EffectsLayer)
  Overlay: 500
  // (6번) HUD 등
};
var BackgroundLayer = class {
  phase = RenderPhase.Background;
  gradient = null;
  gradientFor = null;
  h = 0;
  onResize(layout) {
    this.h = layout.cssH;
    this.gradient = null;
  }
  draw({ ctx, layout }) {
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
};
var GridLayer = class {
  phase = RenderPhase.Grid;
  draw({ ctx, layout, cam, time, reducedMotion }) {
    const gy = levelToY(layout, 0, cam) + layout.blockH;
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
};
var BlocksLayer = class {
  phase = RenderPhase.Blocks;
  draw({ ctx, layout, logic, sprites, cam }) {
    const blocks = logic.blocks;
    const bh = layout.blockH;
    for (let i = 0; i < blocks.length; i++) {
      const b = blocks[i];
      const y = levelToY(layout, b.level, cam);
      if (y > layout.cssH || y < -bh) continue;
      sprites.draw(ctx, b.colorIndex, worldToScreenX(layout, b.x), y, worldToScreenW(layout, b.w));
    }
    if (!logic.isGameOver) {
      const c = logic.current;
      sprites.draw(ctx, c.colorIndex, worldToScreenX(layout, c.x), levelToY(layout, c.level, cam), worldToScreenW(layout, c.w));
    }
  }
};
var PiecesLayer = class {
  phase = RenderPhase.Pieces;
  draw({ ctx, layout, sprites, pieces, cam }) {
    const items = pieces.items;
    ctx.globalAlpha = VIEW_CONFIG.pieceAlpha;
    for (let i = 0; i < items.length; i++) {
      const p = items[i];
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
};

// work/yabol-deploy/src/stack-up/view-stars.ts
function wrap01(v) {
  return v - Math.floor(v);
}
var StarField = class {
  layerCount = VIEW_CONFIG.stars.length;
  /** 레이어별 시작 인덱스 (길이 layerCount + 1). */
  starts;
  u;
  v;
  /** 레이어별 누적 흐름량 (화면 높이 비율). */
  scroll;
  constructor(rand) {
    this.starts = new Int32Array(this.layerCount + 1);
    let total = 0;
    for (let l = 0; l < this.layerCount; l++) {
      this.starts[l] = total;
      total += VIEW_CONFIG.stars[l].count;
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
  update(dt, flowScale) {
    for (let l = 0; l < this.layerCount; l++) {
      this.scroll[l] = wrap01(this.scroll[l] + dt * VIEW_CONFIG.stars[l].drift * flowScale);
    }
  }
  /** 별 i(레이어 l)의 화면 y (CSS px). 카메라가 올라가면 별은 아래로 내려간다 (깊을수록 적게). */
  screenY(i, l, cam, blockH, cssH) {
    const par = VIEW_CONFIG.stars[l].parallax;
    return wrap01(this.v[i] + this.scroll[l] + cam * par * blockH / cssH) * cssH;
  }
};

// work/yabol-deploy/src/stack-up/view-fxLayers.ts
var STARS_PHASE = RenderPhase.Background + 10;
var StarsLayer = class {
  phase = STARS_PHASE;
  field;
  constructor(rand) {
    this.field = new StarField(rand);
  }
  update(dt, f) {
    this.field.update(dt, f.reducedMotion ? VIEW_CONFIG.starFlowReduced : 1);
  }
  draw({ ctx, layout, cam }) {
    const fld = this.field;
    const cfgs = VIEW_CONFIG.stars;
    for (let l = 0; l < fld.layerCount; l++) {
      const cfg = cfgs[l];
      ctx.globalAlpha = cfg.alpha;
      ctx.fillStyle = cfg.color;
      const end = fld.starts[l + 1];
      for (let i = fld.starts[l]; i < end; i++) {
        ctx.fillRect(fld.u[i] * layout.cssW, fld.screenY(i, l, cam, layout.blockH, layout.cssH), cfg.size, cfg.size);
      }
    }
    ctx.globalAlpha = 1;
  }
};
var MILESTONE_FLASH_PHASE = RenderPhase.Grid + 50;
var MilestoneFlashLayer = class {
  phase = MILESTONE_FLASH_PHASE;
  draw({ ctx, layout, effects }) {
    const m = effects.milestone;
    if (!m.active) return;
    const a = milestoneFlashAlpha(m.t, m.dur, m.peak);
    if (a <= 0) return;
    ctx.globalAlpha = a;
    ctx.fillStyle = VIEW_CONFIG.milestoneFlashColors[m.colorIndex % VIEW_CONFIG.milestoneFlashColors.length];
    const b = VIEW_CONFIG.milestoneFlashBleed;
    ctx.fillRect(-b, -b, layout.cssW + b * 2, layout.cssH + b * 2);
    ctx.globalAlpha = 1;
  }
};
var EffectsLayer = class {
  phase = RenderPhase.Effects;
  /** roundRect 지원 여부 (구형 Safari 대비, 한 번만 판정). */
  hasRoundRect = typeof CanvasRenderingContext2D !== "undefined" && typeof CanvasRenderingContext2D.prototype.roundRect === "function";
  /** roundRect가 없으면 arcTo로 같은 경로를 만든다 (할당 없음). */
  rectPath(ctx, x, y, w, h, r0) {
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
  draw({ ctx, layout, cam, effects }) {
    const c = VIEW_CONFIG;
    const bh = layout.blockH;
    const flashes = effects.flashes;
    for (let i = 0; i < flashes.length; i++) {
      const f = flashes[i];
      if (!f.active) continue;
      const p = f.t / f.dur;
      const e = easeOutCubic(p);
      const inset = bh * VIEW_CONFIG.blockInset;
      const y = levelToY(layout, f.level, cam) + inset;
      const h = bh - inset * 2;
      ctx.globalAlpha = 1 - p;
      ctx.lineWidth = c.flashLineWidth;
      if (f.grow > 0) {
        const wNow = f.w - f.grow * (1 - e);
        const cx = worldToScreenX(layout, f.x + f.w / 2);
        const sw = worldToScreenW(layout, wNow);
        ctx.strokeStyle = "#FFFFFF";
        ctx.strokeRect(cx - sw / 2, y, sw, h);
      } else {
        const spread = e * bh * c.flashSpread;
        ctx.strokeStyle = BLOCK_STYLES[f.colorIndex % BLOCK_STYLES.length].stroke;
        ctx.strokeRect(
          worldToScreenX(layout, f.x) - spread,
          y - spread,
          worldToScreenW(layout, f.w) + spread * 2,
          h + spread * 2
        );
      }
    }
    const rings = effects.rings;
    for (let i = 0; i < rings.length; i++) {
      const r = rings[i];
      if (!r.active) continue;
      const p = r.t / r.dur;
      const e = waveProgress(r.t, r.dur);
      const bx = worldToScreenX(layout, r.x - r.w / 2);
      const bw = worldToScreenW(layout, r.w);
      const gxMax = clampWaveGrow(
        layout.playW * r.grow * r.scale,
        bx,
        bw,
        layout.cssW,
        c.ringScreenMargin,
        bh * c.ringMinGrowBlocks
      );
      const gx = gxMax * e;
      const gy = Math.min(c.ringGrowYMax * bh, gx * c.ringGrowYRatio);
      const inset = bh * c.blockInset;
      const by = levelToY(layout, r.y, cam) + inset;
      ctx.globalAlpha = (1 - p) * c.ringAlpha;
      ctx.lineWidth = c.ringLineWidth * (1 - p * (1 - c.ringLineEnd));
      ctx.strokeStyle = r.combo >= c.ringCyanCombo ? c.ringCyan : BLOCK_STYLES[r.colorIndex % BLOCK_STYLES.length].stroke;
      ctx.beginPath();
      this.rectPath(ctx, bx - gx, by - gy, bw + gx * 2, bh - inset * 2 + gy * 2, bh * c.ringCorner);
      ctx.stroke();
    }
    const ps = effects.particles;
    const size = c.particleSize;
    for (let i = 0; i < ps.length; i++) {
      const p = ps[i];
      if (!p.active) continue;
      ctx.globalAlpha = Math.min(1, p.life / p.maxLife);
      ctx.fillStyle = BLOCK_STYLES[p.colorIndex % BLOCK_STYLES.length].stroke;
      ctx.fillRect(worldToScreenX(layout, p.x) - size / 2, levelToY(layout, p.y, cam) - size / 2, size, size);
    }
    ctx.globalAlpha = 1;
  }
};

// work/yabol-deploy/src/stack-up/view-StackUpRenderer.ts
var StackUpRenderer = class {
  constructor(canvas, logic, options = {}) {
    this.canvas = canvas;
    this.logic = logic;
    const ctx = canvas.getContext("2d");
    if (!ctx) throw new Error("Canvas 2D is not available");
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
      time: 0
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
  canvas;
  logic;
  frame;
  ctx;
  sprites = new GlowSprites();
  pieces = new PiecePool();
  layers = [];
  random;
  effects;
  /** onEvent에서 perfect/regrow가 직전 land의 위치를 쓰기 위해 보관 (core는 land → perfect → regrow 순서). */
  landX = 0;
  landW = 0;
  /** phase 순으로 정렬해 삽입 (같은 phase면 먼저 추가한 것이 먼저). 프레임 중 정렬 없음. */
  addLayer(layer) {
    let i = this.layers.length;
    while (i > 0 && this.layers[i - 1].phase > layer.phase) i--;
    this.layers.splice(i, 0, layer);
    layer.onResize?.(this.frame.layout);
  }
  /** 캔버스 크기, dpr, 레이아웃, 글로우 스프라이트를 다시 맞춘다. */
  resize() {
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
  reset() {
    this.frame.cam = 0;
    this.pieces.clear();
    this.effects.clear();
  }
  setReducedMotion(on) {
    this.effects.reducedMotion = on;
    this.frame.reducedMotion = on;
    if (on) this.effects.cancelShake();
  }
  /** core 이벤트 처리. 인자 캡처가 없으므로 그대로 consumeEvents에 넘겨도 된다. */
  onEvent = (e) => {
    if (e.type === "cut") {
      const dir = e.side === "left" ? -1 : 1;
      const vr = dir * (VIEW_CONFIG.pieceSpinMin + this.random() * VIEW_CONFIG.pieceSpinRange);
      this.pieces.spawn(e.x, e.w, e.level, e.colorIndex, vr);
    } else if (e.type === "land") {
      this.landX = e.x;
      this.landW = e.w;
      this.effects.spawnLand(e.x, e.w, e.level, this.colorAt(e.level));
    } else if (e.type === "perfect") {
      this.effects.spawnPerfect(this.landX, this.landW, e.level, this.colorAt(e.level), e.combo);
    } else if (e.type === "regrow") {
      this.effects.spawnRegrow(this.landX, this.landW, e.level, e.amount, this.colorAt(e.level));
    } else if (e.type === "milestone") {
      this.effects.spawnMilestone();
    } else if (e.type === "gameOver") {
      this.effects.startShake();
      const vr = (this.random() - 0.5) * VIEW_CONFIG.dropSpin;
      this.pieces.spawn(e.x, e.w, e.level, e.colorIndex, vr);
    }
  };
  colorAt(level) {
    return this.logic.blocks[level]?.colorIndex ?? 0;
  }
  update(dt) {
    const f = this.frame;
    f.time += dt;
    f.cam = stepCamera(f.cam, cameraTarget(this.logic.floors, f.layout.followLevels), dt);
    this.pieces.update(dt, f.layout, f.cam);
    this.effects.update(dt);
    for (let i = 0; i < this.layers.length; i++) this.layers[i].update?.(dt, f);
  }
  render() {
    const f = this.frame;
    const d = f.layout.dpr;
    this.ctx.setTransform(d, 0, 0, d, 0, 0);
    const sh = this.effects.shake;
    const ox = sh.x * f.layout.blockH * d;
    const oy = sh.y * f.layout.blockH * d;
    let shaken = false;
    for (let i = 0; i < this.layers.length; i++) {
      const l = this.layers[i];
      if (!shaken && l.phase >= RenderPhase.Grid) {
        this.ctx.setTransform(d, 0, 0, d, ox, oy);
        shaken = true;
      }
      l.draw(f);
    }
  }
};
export {
  StackUpLogic,
  StackUpRenderer,
  createRng
};
