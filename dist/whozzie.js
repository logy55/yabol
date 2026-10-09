// Whozzie ladder engine, Copyright (c) 2025 zeikar, MIT. See whozzie-LICENSE.txt.

// outputs/community-site/src/vendor/whozzie/random.ts
var UINT32_RANGE = 2 ** 32;
function randomInt(maxExclusive) {
  if (!Number.isInteger(maxExclusive) || maxExclusive < 1 || maxExclusive > UINT32_RANGE) {
    throw new RangeError(`randomInt: expected an integer in [1, 2^32], got ${maxExclusive}`);
  }
  const limit = UINT32_RANGE - UINT32_RANGE % maxExclusive;
  const buffer = new Uint32Array(1);
  let value;
  do {
    crypto.getRandomValues(buffer);
    value = buffer[0];
  } while (value >= limit);
  return value % maxExclusive;
}
function randomFloat() {
  const buffer = new Uint32Array(1);
  crypto.getRandomValues(buffer);
  return buffer[0] / UINT32_RANGE;
}
function shuffle(items) {
  const result = [...items];
  for (let i = result.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [result[i], result[j]] = [result[j], result[i]];
  }
  return result;
}
function seededRandom(seed) {
  let state = seed >>> 0;
  return () => {
    state = state + 1831565813 >>> 0;
    let t = state;
    t = Math.imul(t ^ t >>> 15, t | 1);
    t ^= t + Math.imul(t ^ t >>> 7, t | 61);
    return ((t ^ t >>> 14) >>> 0) / UINT32_RANGE;
  };
}
function hashString(value) {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

// outputs/community-site/src/vendor/whozzie/ladder.ts
var MIN_PLAYERS = 2;
var MAX_PLAYERS = 12;
var isPlayable = (count) => count >= MIN_PLAYERS && count <= MAX_PLAYERS;
var cryptoRng = { int: randomInt, float: randomFloat };
var rungChance = (rows) => Math.min(0.55, 5 / rows);
var rowsFor = (columns) => Math.max(8, columns * 2);
function generateLadder(columns, rng = cryptoRng) {
  const rows = rowsFor(columns);
  const gaps = columns - 1;
  const rungs = Array.from({ length: rows }, () => new Array(gaps).fill(false));
  const free = (row, gap) => !rungs[row][gap] && !rungs[row][gap - 1] && !rungs[row][gap + 1] && !rungs[row - 1]?.[gap] && !rungs[row + 1]?.[gap];
  for (let gap = 0; gap < gaps; gap++) {
    const open = Array.from({ length: rows }, (_, row) => row).filter((row) => free(row, gap));
    rungs[open[rng.int(open.length)]][gap] = true;
  }
  const chance = rungChance(rows);
  for (let row = 0; row < rows; row++) {
    for (let gap = 0; gap < gaps; gap++) {
      if (free(row, gap) && rng.float() < chance) rungs[row][gap] = true;
    }
  }
  return { columns, rows, rungs };
}
function trace(ladder, start) {
  let column = start;
  const points = [[column, 0]];
  ladder.rungs.forEach((row, r) => {
    const next = row[column] ? column + 1 : row[column - 1] ? column - 1 : column;
    if (next === column) return;
    points.push([column, r + 0.5], [next, r + 0.5]);
    column = next;
  });
  points.push([column, ladder.rows]);
  return { end: column, points };
}
function dealRound(players, rng = cryptoRng) {
  const ladder = generateLadder(players, rng);
  const order = Array.from({ length: players }, (_, i) => i);
  const seats = shuffle(order);
  const slots = shuffle(order);
  const lanes = seats.map((player, column) => {
    const { end, points } = trace(ladder, column);
    return { player, result: slots[end], end, points };
  });
  return { ladder, lanes };
}

// outputs/community-site/src/vendor/whozzie/sketch.ts
var round = (value) => Math.round(value * 100) / 100;

// outputs/community-site/src/vendor/whozzie/geometry.ts
var MIN_GAP = 51;
var MAX_GAP = 120;
var STAGGER_BELOW = 96;
var STAGGER_GUTTER = 0.9;
var CHIP_HEIGHT = 40;
var FLAP_HEIGHT = 44;
var MAX_FLAP_WIDTH = 92;
var ROW_STEP = 46;
var MARGIN = 14;
var TAPE_OVERHANG = { x: 6, y: 4 };
var minBoardWidth = (columns) => (columns + STAGGER_GUTTER) * MIN_GAP;
var maxBoardWidth = (columns) => columns * MAX_GAP;
function layout(width, ladder) {
  const { columns, rows } = ladder;
  const stagger = width / columns < STAGGER_BELOW;
  const spacing = width / (columns + (stagger ? STAGGER_GUTTER : 0));
  const inset = stagger ? spacing * STAGGER_GUTTER / 2 : 0;
  const chipTop = (column) => stagger && column % 2 === 1 ? ROW_STEP : 0;
  const ladderTop = CHIP_HEIGHT + (stagger ? ROW_STEP : 0) + MARGIN;
  const rowHeight = Math.max(26, 320 / rows);
  const ladderBottom = ladderTop + rows * rowHeight;
  const flapTop = (column) => ladderBottom + MARGIN + (stagger && column % 2 === 1 ? ROW_STEP : 0);
  return {
    height: ladderBottom + MARGIN + (stagger ? ROW_STEP : 0) + FLAP_HEIGHT,
    // Names may reach almost to the neighbouring lines; results stay clear of them.
    labelWidth: stagger ? 2 * spacing - 12 : spacing - 8,
    flapWidth: Math.min(stagger ? 2 * spacing - 28 : spacing - 20, MAX_FLAP_WIDTH),
    x: (column) => inset + (column + 0.5) * spacing,
    /**
     * A rung's height, nudged up to a quarter row off its grid line so the rungs
     * don't line up like a table. Rungs on the same line are at least a row apart,
     * so the nudge never changes their order.
     */
    rungY: (row, gap) => ladderTop + (row + 0.5 + (seededRandom(hashString(`${row}:${gap}`))() - 0.5) * 0.5) * rowHeight,
    chipTop,
    lineTop: (column) => chipTop(column) + CHIP_HEIGHT,
    flapTop
  };
}
function lanePath(lane, geometry) {
  const last = lane.points.length - 1;
  const points = lane.points.map(([column, y], i) => {
    const x = geometry.x(column);
    if (i === 0) return [x, geometry.lineTop(column)];
    if (i === last) return [x, geometry.flapTop(column)];
    const across = lane.points[i % 2 === 1 ? i + 1 : i - 1][0];
    return [x, geometry.rungY(y - 0.5, Math.min(column, across))];
  });
  const d = points.map(([x, y], i) => `${i === 0 ? "M" : "L"}${round(x)} ${round(y)}`).join("");
  const length = points.slice(1).reduce((sum, [x, y], i) => sum + Math.hypot(x - points[i][0], y - points[i][1]), 0);
  return { d, length };
}
function scrollToShow(from, to, pad, scrollLeft, view) {
  const [left, right] = from < to ? [from, to] : [to, from];
  if (left - pad >= scrollLeft && right + pad <= scrollLeft + view) return null;
  const centre = right - left + 2 * pad <= view ? (left + right) / 2 : from;
  return centre - view / 2;
}
var MS_PER_PX = 2.2;
var TRACE_MS = { min: 1500, max: 2500 };
var PEEL_MS = 420;
var REVEAL_ALL_MS = 1e4;
var MIN_PACE = 0.4;
function traceTiming(length, lines) {
  const trace2 = Math.min(Math.max(length * MS_PER_PX, TRACE_MS.min), TRACE_MS.max);
  const pace = Math.min(1, Math.max(MIN_PACE, REVEAL_ALL_MS / (lines * (TRACE_MS.max + PEEL_MS))));
  return { trace: trace2 * pace, peel: PEEL_MS * pace };
}
export {
  CHIP_HEIGHT,
  FLAP_HEIGHT,
  MAX_PLAYERS,
  MIN_PLAYERS,
  PEEL_MS,
  REVEAL_ALL_MS,
  TAPE_OVERHANG,
  TRACE_MS,
  dealRound,
  generateLadder,
  isPlayable,
  lanePath,
  layout,
  maxBoardWidth,
  minBoardWidth,
  rowsFor,
  scrollToShow,
  trace,
  traceTiming
};
