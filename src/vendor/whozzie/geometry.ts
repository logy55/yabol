/**
 * The board in px: where the lines, rungs, names and taped-over results sit on a
 * board `width` px wide, and how long following a path down it takes.
 */

import { hashString, seededRandom } from "./random";
import { round } from "./sketch";
import type { Ladder, Lane } from "./ladder";

/** Lines closer than this get cramped, so the board scrolls sideways instead. Six still fit a 390px phone. */
const MIN_GAP = 51;
const MAX_GAP = 120;
/** Below this spacing a name can't sit over its own line; names alternate between two rows. */
const STAGGER_BELOW = 96;
/** Alternating labels reach past their own line; the outer ones get this many gaps of room. */
const STAGGER_GUTTER = 0.9;
export const CHIP_HEIGHT = 40;
export const FLAP_HEIGHT = 44;
const MAX_FLAP_WIDTH = 92;
/** How far the second row of names (and results) sits from the first. */
const ROW_STEP = 46;
const MARGIN = 14;
/** How far the masking tape reaches past the result it covers. */
export const TAPE_OVERHANG = { x: 6, y: 4 };

/** Narrow enough to scroll means staggered, which adds the gutter. */
export const minBoardWidth = (columns: number) => (columns + STAGGER_GUTTER) * MIN_GAP;
export const maxBoardWidth = (columns: number) => columns * MAX_GAP;

export type Geometry = ReturnType<typeof layout>;

/** Where everything goes for a board `width` px wide. */
export function layout(width: number, ladder: Ladder) {
  const { columns, rows } = ladder;
  const stagger = width / columns < STAGGER_BELOW;
  const spacing = width / (columns + (stagger ? STAGGER_GUTTER : 0));
  const inset = stagger ? (spacing * STAGGER_GUTTER) / 2 : 0;
  // Top: even columns take the far row. Bottom: odd ones do. Every line gets one long stub.
  const chipTop = (column: number) => (stagger && column % 2 === 1 ? ROW_STEP : 0);
  const ladderTop = CHIP_HEIGHT + (stagger ? ROW_STEP : 0) + MARGIN;
  const rowHeight = Math.max(26, 320 / rows);
  const ladderBottom = ladderTop + rows * rowHeight;
  const flapTop = (column: number) => ladderBottom + MARGIN + (stagger && column % 2 === 1 ? ROW_STEP : 0);

  return {
    height: ladderBottom + MARGIN + (stagger ? ROW_STEP : 0) + FLAP_HEIGHT,
    // Names may reach almost to the neighbouring lines; results stay clear of them.
    labelWidth: stagger ? 2 * spacing - 12 : spacing - 8,
    flapWidth: Math.min(stagger ? 2 * spacing - 28 : spacing - 20, MAX_FLAP_WIDTH),
    x: (column: number) => inset + (column + 0.5) * spacing,
    /**
     * A rung's height, nudged up to a quarter row off its grid line so the rungs
     * don't line up like a table. Rungs on the same line are at least a row apart,
     * so the nudge never changes their order.
     */
    rungY: (row: number, gap: number) =>
      ladderTop + (row + 0.5 + (seededRandom(hashString(`${row}:${gap}`))() - 0.5) * 0.5) * rowHeight,
    chipTop,
    lineTop: (column: number) => chipTop(column) + CHIP_HEIGHT,
    flapTop,
  };
}

/** A lane's path in px, from under the player's name to the top of their result. */
export function lanePath(lane: Lane, geometry: Geometry) {
  const last = lane.points.length - 1;
  const points = lane.points.map(([column, y], i) => {
    const x = geometry.x(column);
    if (i === 0) return [x, geometry.lineTop(column)];
    if (i === last) return [x, geometry.flapTop(column)];
    // Between start and end the points come in pairs: the two ends of one rung.
    const across = lane.points[i % 2 === 1 ? i + 1 : i - 1][0];
    return [x, geometry.rungY(y - 0.5, Math.min(column, across))];
  });
  const d = points.map(([x, y], i) => `${i === 0 ? "M" : "L"}${round(x)} ${round(y)}`).join("");
  const length = points.slice(1).reduce((sum, [x, y], i) => sum + Math.hypot(x - points[i][0], y - points[i][1]), 0);
  return { d, length };
}

/**
 * Where to scroll a board wider than the screen (`view` px wide, scrolled to
 * `scrollLeft`) so both ends of a line, at `from` and `to` px, show with `pad` px
 * around them; null when they already do. When both can't fit, `from` leads.
 */
export function scrollToShow(from: number, to: number, pad: number, scrollLeft: number, view: number) {
  const [left, right] = from < to ? [from, to] : [to, from];
  if (left - pad >= scrollLeft && right + pad <= scrollLeft + view) return null;
  const centre = right - left + 2 * pad <= view ? (left + right) / 2 : from;
  return centre - view / 2;
}

/** A single trace speeds up on short paths and slows on long ones, within TRACE_MS. */
const MS_PER_PX = 2.2;
export const TRACE_MS = { min: 1500, max: 2500 };
export const PEEL_MS = 420;
/** Reveal all speeds its traces up to finish in about this long... */
export const REVEAL_ALL_MS = 10_000;
/** ...but never runs them faster than this share of their usual time, or they'd be hard to follow. */
const MIN_PACE = 0.4;

/**
 * How long tracing a path `length` px long takes, and peeling the tape off after,
 * when it's one of `lines` traced back to back.
 */
export function traceTiming(length: number, lines: number) {
  const trace = Math.min(Math.max(length * MS_PER_PX, TRACE_MS.min), TRACE_MS.max);
  const pace = Math.min(1, Math.max(MIN_PACE, REVEAL_ALL_MS / (lines * (TRACE_MS.max + PEEL_MS))));
  return { trace: trace * pace, peel: PEEL_MS * pace };
}
