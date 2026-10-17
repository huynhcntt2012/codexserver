/**
 * Protocol v2 maps: the same layouts the PC app ships in apps/practice/levels/*.json
 * (tests keep the two in sync): three classic 15 x 11 maps and the twelve 17 x 13
 * Boom World maps. `#` wall, `C` crate.
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

/** Boom World maps: 4 corner spawns from the pack plus 4 edge midpoints for 8 seats. */
const SPAWNS_17X13 = [
  [1, 1],
  [15, 11],
  [15, 1],
  [1, 11],
  [8, 1],
  [8, 11],
  [1, 6],
  [15, 6],
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
  pastry: {
    id: 'pastry',
    name: 'TIỆM BÁNH MÂY',
    tier: 'Dễ',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#....CC...CC....#',
      '#.#C#.#.#.#.#C#.#',
      '#.C..C.C.C.C..C.#',
      '#.#C#.#.#.#.#C#.#',
      '#...............#',
      '#C#.#.#.#.#.#.#C#',
      '#...............#',
      '#.#C#.#.#.#.#C#.#',
      '#.C..C.C.C.C..C.#',
      '#.#C#.#.#.#.#C#.#',
      '#....CC...CC....#',
      '#################',
    ],
  },
  forest: {
    id: 'forest',
    name: 'RỪNG NẤM ĐOM ĐÓM',
    tier: 'Trung bình',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#...CCC...CCC...#',
      '#.#C#.#C#C#.#C#.#',
      '#.C..C.....C..C.#',
      '#.#.#C#.#.#C#.#.#',
      '#C..C.CC.CC.C..C#',
      '#C#C#C#C#C#C#C#C#',
      '#C..C.CC.CC.C..C#',
      '#.#.#C#.#.#C#.#.#',
      '#.C..C.....C..C.#',
      '#.#C#.#C#C#.#C#.#',
      '#...CCC...CCC...#',
      '#################',
    ],
  },
  harbor: {
    id: 'harbor',
    name: 'BẾN CẢNG BONG BÓNG',
    tier: 'Trung bình',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#...CCC...CCC...#',
      '#.#.#.#.#.#.#.#.#',
      '#.C.C.C...C.C.C.#',
      '#.#.#C#.#.#C#.#.#',
      '#...............#',
      '#.#.#C#.#.#C#.#.#',
      '#...............#',
      '#.#.#C#.#.#C#.#.#',
      '#.C.C.C...C.C.C.#',
      '#.#.#.#.#.#.#.#.#',
      '#...CCC...CCC...#',
      '#################',
    ],
  },
  station: {
    id: 'station',
    name: 'GA TÀU CẦU VỒNG',
    tier: 'Trung bình',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#.....C.C.C.....#',
      '#.#.#C#C#C#C#.#.#',
      '#..CCC.....CCC..#',
      '#.#.#C#C#C#C#.#.#',
      '#..C.........C..#',
      '#C#.#C#.#.#C#.#C#',
      '#..C.........C..#',
      '#.#.#C#C#C#C#.#.#',
      '#..CCC.....CCC..#',
      '#.#.#C#C#C#C#.#.#',
      '#.....C.C.C.....#',
      '#################',
    ],
  },
  clock: {
    id: 'clock',
    name: 'THÁP ĐỒNG HỒ',
    tier: 'Khó',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#....C..C..C....#',
      '#.#C#C#.#.#C#C#.#',
      '#.CCC.......CCC.#',
      '#.#C#.#C#C#.#C#.#',
      '#C.............C#',
      '#.#C#.#.#.#.#C#.#',
      '#C.............C#',
      '#.#C#.#C#C#.#C#.#',
      '#.CCC.......CCC.#',
      '#.#C#C#.#.#C#C#.#',
      '#....C..C..C....#',
      '#################',
    ],
  },
  crystal: {
    id: 'crystal',
    name: 'HANG PHA LÊ',
    tier: 'Trung bình',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#......CCC......#',
      '#.#.#.#C#C#.#.#.#',
      '#.....C...C.....#',
      '#C#.#.#.#.#.#.#C#',
      '#C..C.......C..C#',
      '#.#C#.#.#.#.#C#.#',
      '#C..C.......C..C#',
      '#C#.#.#.#.#.#.#C#',
      '#.....C...C.....#',
      '#.#.#.#C#C#.#.#.#',
      '#......CCC......#',
      '#################',
    ],
  },
  market: {
    id: 'market',
    name: 'CHỢ ĐÊM ĐÈN LỒNG',
    tier: 'Trung bình',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#....C.....C....#',
      '#.#C#C#.#.#C#C#.#',
      '#..C..CC.CC..C..#',
      '#C#C#C#.#.#C#C#C#',
      '#...............#',
      '#.#.#.#.#.#.#.#.#',
      '#...............#',
      '#C#C#C#.#.#C#C#C#',
      '#..C..CC.CC..C..#',
      '#.#C#C#.#.#C#C#.#',
      '#....C.....C....#',
      '#################',
    ],
  },
  sky: {
    id: 'sky',
    name: 'ĐỀN GIÓ TRÊN MÂY',
    tier: 'Khó',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#......CCC......#',
      '#.#.#.#.#.#.#.#.#',
      '#..C....C....C..#',
      '#.#.#.#.#.#.#.#.#',
      '#.C...........C.#',
      '#.#.#.#.#.#.#.#.#',
      '#.C...........C.#',
      '#.#.#.#.#.#.#.#.#',
      '#..C....C....C..#',
      '#.#.#.#.#.#.#.#.#',
      '#......CCC......#',
      '#################',
    ],
  },
  volcano: {
    id: 'volcano',
    name: 'NÚI LỬA KẸO ĐỎ',
    tier: 'Khó',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#...CCC...CCC...#',
      '#.#.#.#.#.#.#.#.#',
      '#.CC...CCC...CC.#',
      '#C#C#.#.#.#.#C#C#',
      '#CC..C..C..C..CC#',
      '#.#.#.#.#.#.#.#.#',
      '#CC..C..C..C..CC#',
      '#C#C#.#.#.#.#C#C#',
      '#.CC...CCC...CC.#',
      '#.#.#.#.#.#.#.#.#',
      '#...CCC...CCC...#',
      '#################',
    ],
  },
  star: {
    id: 'star',
    name: 'VƯỜN SAO RƠI',
    tier: 'Trung bình',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#.....CCCCC.....#',
      '#.#C#C#.#.#C#C#.#',
      '#.C.C.......C.C.#',
      '#.#C#.#C#C#.#C#.#',
      '#CCC.C.....C.CCC#',
      '#.#.#C#.#.#C#.#.#',
      '#CCC.C.....C.CCC#',
      '#.#C#.#C#C#.#C#.#',
      '#.C.C.......C.C.#',
      '#.#C#C#.#.#C#C#.#',
      '#.....CCCCC.....#',
      '#################',
    ],
  },
  factory: {
    id: 'factory',
    name: 'XƯỞNG ROBOT KẸO',
    tier: 'Khó',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#...CC.CCC.CC...#',
      '#.#.#C#.#.#C#.#.#',
      '#.......C.......#',
      '#.#C#C#C#C#C#C#.#',
      '#CC.CCCC.CCCC.CC#',
      '#C#.#.#.#.#.#.#C#',
      '#CC.CCCC.CCCC.CC#',
      '#.#C#C#C#C#C#C#.#',
      '#.......C.......#',
      '#.#.#C#.#.#C#.#.#',
      '#...CC.CCC.CC...#',
      '#################',
    ],
  },
  moon: {
    id: 'moon',
    name: 'CUNG ĐIỆN TRĂNG',
    tier: 'Khó',
    width: 17,
    height: 13,
    spawns: SPAWNS_17X13,
    layout: [
      '#################',
      '#...C..C.C..C...#',
      '#.#C#C#C#C#C#C#.#',
      '#.....C...C.....#',
      '#.#.#.#.#.#.#.#.#',
      '#..CCC.....CCC..#',
      '#.#C#.#.#.#.#C#.#',
      '#..CCC.....CCC..#',
      '#.#.#.#.#.#.#.#.#',
      '#.....C...C.....#',
      '#.#C#C#C#C#C#C#.#',
      '#...C..C.C..C...#',
      '#################',
    ],
  },
};

/** Cosmetic hero ids the client may ask for; anything else falls back by slot. */
export const HEROES = ['bombo', 'mimi', 'zin', 'lala', 'kai'] as const;

// ---------------------------------------------------------------- admin maps

/** Shape of one entry of the API's public `GET /v1/maps` (admin-published maps). */
interface RemoteLevel {
  id?: unknown;
  name?: unknown;
  subtitle?: unknown;
  columns?: unknown;
  rows?: unknown;
  layout?: unknown;
  arena_spawns?: unknown;
}

const REMOTE_TTL_MS = 15_000;
let remote: { at: number; maps: Map<string, MapDef> } | null = null;
let pending: Promise<Map<string, MapDef>> | null = null;

/**
 * Rebuilds a MapDef from the API, re-checking everything the simulation relies on
 * (the API validates on save; the arena never trusts a layout it cannot use).
 */
export function toMapDef(level: RemoteLevel): MapDef | null {
  const {
    id,
    name,
    columns: width,
    rows: height,
    layout,
    arena_spawns,
  } = level;
  if (
    typeof id !== 'string' ||
    !/^[a-z][a-z0-9_]{2,23}$/.test(id) ||
    Object.hasOwn(MAPS, id) ||
    typeof name !== 'string' ||
    name.length > 40 ||
    typeof width !== 'number' ||
    typeof height !== 'number' ||
    !Number.isInteger(width) ||
    !Number.isInteger(height) ||
    width < 11 ||
    width > 21 ||
    height < 9 ||
    height > 17 ||
    !Array.isArray(layout) ||
    layout.length !== height ||
    !layout.every(
      (row) =>
        typeof row === 'string' &&
        row.length === width &&
        /^#[#C.]*#$/.test(row),
    ) ||
    !/^#+$/.test(layout[0] as string) ||
    !/^#+$/.test(layout[height - 1] as string) ||
    !Array.isArray(arena_spawns) ||
    arena_spawns.length !== 8
  )
    return null;
  const spawns: [number, number][] = [];
  for (const spawn of arena_spawns as unknown[]) {
    if (
      !Array.isArray(spawn) ||
      spawn.length !== 2 ||
      !spawn.every((n) => Number.isInteger(n))
    )
      return null;
    const [x, y] = spawn as [number, number];
    if (x < 1 || y < 1 || x >= width - 1 || y >= height - 1) return null;
    if ((layout[y] as string)[x] === '#') return null;
    spawns.push([x, y]);
  }
  if (new Set(spawns.map((s) => s.join(','))).size !== 8) return null;
  const subtitle = typeof level.subtitle === 'string' ? level.subtitle : '';
  return {
    id,
    name,
    tier: subtitle.split('•')[0]?.trim() ?? '',
    width,
    height,
    layout: layout as string[],
    spawns,
  };
}

async function fetchRemote(): Promise<Map<string, MapDef>> {
  const base = process.env.API_URL;
  const maps = new Map<string, MapDef>();
  if (!base) return maps;
  const response = await fetch(`${base}/v1/maps`, {
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) throw new Error(`API ${response.status}`);
  const body = (await response.json()) as { maps?: unknown };
  for (const level of Array.isArray(body.maps) ? body.maps : []) {
    const def = toMapDef(level as RemoteLevel);
    if (def) maps.set(def.id, def);
  }
  return maps;
}

/** Published admin maps, cached for 15 s; the last good list survives API errors. */
export async function remoteMaps(): Promise<Map<string, MapDef>> {
  if (remote && Date.now() - remote.at < REMOTE_TTL_MS) return remote.maps;
  pending ??= fetchRemote()
    .then((maps) => {
      remote = { at: Date.now(), maps };
      return maps;
    })
    .catch(() => remote?.maps ?? new Map<string, MapDef>())
    .finally(() => {
      pending = null;
    });
  return pending;
}

/** Built-in map, or a published admin map from the API; null when unknown. */
export async function findMap(id: unknown): Promise<MapDef | null> {
  if (typeof id !== 'string') return null;
  if (Object.hasOwn(MAPS, id)) return MAPS[id]!;
  return (await remoteMaps()).get(id) ?? null;
}

/** Test hook: forget cached admin maps. */
export function resetRemoteMaps(): void {
  remote = null;
}
