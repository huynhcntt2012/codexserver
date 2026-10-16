/**
 * Protocol v2 maps: the same 15 x 11 layouts the PC app ships in
 * apps/practice/levels/*.json (tests keep the two in sync). `#` wall, `C` crate.
 * The server owns the rules; crates near the eight spawns are cleared so every
 * player starts with an escape route, exactly like the v1 map.
 */
export interface MapDef {
  id: string;
  name: string;
  tier: string;
  width: number;
  height: number;
  layout: readonly string[];
  spawns: readonly (readonly [number, number])[];
}

const SPAWNS_15X11 = [
  [1, 1],
  [13, 9],
  [13, 1],
  [1, 9],
  [7, 1],
  [7, 9],
  [1, 5],
  [13, 5],
] as const;

export const MAPS: Record<string, MapDef> = {
  park: {
    id: 'park',
    name: 'CÔNG VIÊN KẸO',
    tier: 'Dễ',
    width: 15,
    height: 11,
    spawns: SPAWNS_15X11,
    layout: [
      '###############',
      '#.......C.....#',
      '#.#.#.#.#C#.#.#',
      '#...C.C..CC...#',
      '#.#C#C#.#C#.#.#',
      '#.............#',
      '#.#C#.#.#.#.#.#',
      '#...C.........#',
      '#.#.#C#.#.#.#.#',
      '#.....C.......#',
      '###############',
    ],
  },
  frost: {
    id: 'frost',
    name: 'LÂU ĐÀI BĂNG',
    tier: 'Trung bình',
    width: 15,
    height: 11,
    spawns: SPAWNS_15X11,
    layout: [
      '###############',
      '#.............#',
      '#.#.#C#.#C#.#.#',
      '#...CC.#CC....#',
      '#.#C#C#C#.#.#.#',
      '#.CC.#C.C#.CC.#',
      '#.#.#.#.#C#C#.#',
      '#...CC.#......#',
      '#.#.#.#.#.#.#.#',
      '#......CC.....#',
      '###############',
    ],
  },
  coast: {
    id: 'coast',
    name: 'ĐẢO NẮNG VÀNG',
    tier: 'Khó',
    width: 15,
    height: 11,
    spawns: SPAWNS_15X11,
    layout: [
      '###############',
      '#.......C.....#',
      '#.#.#C#C#.#.#.#',
      '#...C#CCC#C...#',
      '#.#.#C#C#.#C#.#',
      '#.CCCCCCC.CCC.#',
      '#.#.#.#.#C#C#.#',
      '#...C#...#C...#',
      '#.#.#C#C#.#.#.#',
      '#.....C.......#',
      '###############',
    ],
  },
};

/** Cosmetic hero ids the client may ask for; anything else falls back by slot. */
export const HEROES = ['bombo', 'mimi', 'zin', 'lala', 'kai'] as const;

export function isMapId(value: unknown): value is string {
  return typeof value === 'string' && Object.hasOwn(MAPS, value);
}
