/**
 * The ladder game (Amidakuji). Players stand on top of vertical lines; rungs join
 * neighbouring lines, and whoever walks down a line crosses every rung they meet.
 * Geometry is in grid units: x is the line (column), y runs from 0 at the top
 * to `rows` at the bottom, and rung row r sits at y = r + 0.5.
 */

import { randomFloat, randomInt, shuffle } from "./random";

export const MIN_PLAYERS = 2;
export const MAX_PLAYERS = 12;

export const isPlayable = (count: number) => count >= MIN_PLAYERS && count <= MAX_PLAYERS;

export type Ladder = {
  columns: number;
  rows: number;
  /** rungs[row][gap] joins line `gap` to line `gap + 1` at that row. */
  rungs: readonly (readonly boolean[])[];
};

export type Rng = { int: (maxExclusive: number) => number; float: () => number };

const cryptoRng: Rng = { int: randomInt, float: randomFloat };

/**
 * Chance of an extra rung at each free spot, on top of the one every pair gets.
 * It thins out as rows are added, so every size ends up with about 3–4 rungs per pair.
 */
const rungChance = (rows: number) => Math.min(0.55, 5 / rows);

export const rowsFor = (columns: number) => Math.max(8, columns * 2);

export function generateLadder(columns: number, rng: Rng = cryptoRng): Ladder {
  const rows = rowsFor(columns);
  const gaps = columns - 1;
  const rungs = Array.from({ length: rows }, () => new Array<boolean>(gaps).fill(false));
  // A rung can't share a line with another rung in its row, or the path would fork.
  // Nor does it go right under another in the same gap: the path would just zigzag back.
  const free = (row: number, gap: number) =>
    !rungs[row][gap] &&
    !rungs[row][gap - 1] &&
    !rungs[row][gap + 1] &&
    !rungs[row - 1]?.[gap] &&
    !rungs[row + 1]?.[gap];

  // One rung per pair first, so every line is joined to its neighbours. Only the
  // previous gap has a rung yet, so at least rows - 1 rows are open.
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

export type Point = readonly [column: number, y: number];

/** Walks down from `start`, crossing every rung met. Returns where it ends and the path taken. */
export function trace(ladder: Ladder, start: number): { end: number; points: Point[] } {
  let column = start;
  const points: Point[] = [[column, 0]];
  ladder.rungs.forEach((row, r) => {
    const next = row[column] ? column + 1 : row[column - 1] ? column - 1 : column;
    if (next === column) return;
    points.push([column, r + 0.5], [next, r + 0.5]);
    column = next;
  });
  points.push([column, ladder.rows]);
  return { end: column, points };
}

/** One line of a dealt round, read from the top. */
export type Lane = {
  /** Index in the names list of the player standing on this line. */
  player: number;
  /** Index of the result their path lands on. */
  result: number;
  /** The line their path ends on, where that result sits. */
  end: number;
  points: Point[];
};

export type Round = {
  ladder: Ladder;
  /** lanes[column]: the player starting at that column and where they land. */
  lanes: readonly Lane[];
};

/**
 * A fresh ladder with players seated on top and results hidden along the bottom.
 *
 * The rungs alone don't make a fair draw: a line with few rungs mostly runs
 * straight down, so the one standing on it most likely gets the result below.
 * Seating the players in a uniformly shuffled order fixes that for any ladder —
 * a uniform permutation composed with the ladder's fixed one is still uniform —
 * so each player lands on each result with probability 1/n however the rungs fall.
 * The results are shuffled along the bottom too, so the covered slots don't give
 * away which one is which.
 */
export function dealRound(players: number, rng: Rng = cryptoRng): Round {
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
