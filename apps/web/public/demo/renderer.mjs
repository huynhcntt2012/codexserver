const load = (path) => {
  const image = new Image();
  image.src = '/demo/art/boom/' + path;
  return image;
};
const names = ['bombo', 'mimi', 'zin', 'lala', 'kai'];
const sheets = names.map((n) => load(`spritesheets/${n}.png`));
const floor = ['0_0', '0_1', '1_0', '1_1'].map((n) =>
  load(`tiles/grass/${n}.png`),
);
const wall = load('obstacles/stone_wall/00.png');
const crate = load('obstacles/wood_crate/00.png');
const bomb = load('bombs/water_blue.png');
const splash = Array.from({ length: 6 }, (_, i) =>
  load(`effects/water_splash/0${i}.png`),
);
const canvases = new WeakMap();
const ready = (image) => image.complete && image.naturalWidth > 0;
export function drawBoard(
  canvas,
  snapshot,
  localId,
  time,
  selected = null,
  positions = new Map(),
) {
  const ctx = canvas.getContext('2d'),
    cell = 48;
  let state = canvases.get(canvas);
  if (
    !state ||
    state.round !== snapshot?.round ||
    snapshot?.phase !== 'playing'
  ) {
    state = { round: snapshot?.round, players: new Map() };
    canvases.set(canvas, state);
  }
  const draw = (image, x, y, w = cell, h = cell) => {
    if (ready(image)) ctx.drawImage(image, x, y, w, h);
  };
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.fillStyle = '#7da951';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  for (let y = 0; y < 13; y++)
    for (let x = 0; x < 15; x++) {
      draw(floor[(x * 7 + y * 3) % 4], x * cell, y * cell);
      const tile =
        snapshot?.grid[y]?.[x] ??
        (x === 0 ||
        y === 0 ||
        x === 14 ||
        y === 12 ||
        (x % 2 === 0 && y % 2 === 0)
          ? 1
          : 0);
      if (tile === 1) draw(wall, x * cell, y * cell);
      if (tile === 2) draw(crate, x * cell, y * cell);
    }
  for (const b of snapshot?.bombs || []) {
    const size = 40 + Math.sin(time / 100) * 2;
    draw(
      bomb,
      b.x * cell + (cell - size) / 2,
      b.y * cell + (cell - size) / 2,
      size,
      size,
    );
  }
  for (const f of snapshot?.flames || []) {
    const frame = Math.min(
      5,
      Math.max(0, Math.floor(((500 - (f.expiresAt - snapshot.now)) / 500) * 6)),
    );
    draw(splash[frame], f.x * cell, f.y * cell);
  }
  const active = new Set();
  for (const p of snapshot?.players || []) {
    active.add(p.id);
    const pos = positions.get(p.id) ?? p;
    const previous = state.players.get(p.id) ?? {
      x: pos.x,
      y: pos.y,
      row: 1,
      until: 0,
    };
    const dx = pos.x - previous.x,
      dy = pos.y - previous.y;
    if (Math.hypot(dx, dy) > 0.001) {
      previous.row =
        Math.abs(dx) > Math.abs(dy) ? (dx > 0 ? 4 : 3) : dy > 0 ? 1 : 2;
      previous.until = time + 100;
    }
    const row = !p.alive
      ? 9
      : snapshot.phase === 'finished' && snapshot.winner === p.id
        ? 8
        : time < previous.until
          ? previous.row
          : 0;
    state.players.set(p.id, { ...previous, x: pos.x, y: pos.y });
    const sheet =
      sheets[p.id === localId && selected !== null ? selected : p.slot % 5];
    const x = pos.x * cell,
      y = pos.y * cell;
    if (p.id === localId && p.alive) {
      ctx.strokeStyle = '#fff0a3';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.ellipse(x + 24, y + 39, 20, 7, 0, 0, Math.PI * 2);
      ctx.stroke();
    }
    if (ready(sheet))
      ctx.drawImage(
        sheet,
        (Math.floor(time / 166) % 2) * 64,
        row * 64,
        64,
        64,
        x,
        y - 3,
        48,
        48,
      );
  }
  for (const id of state.players.keys())
    if (!active.has(id)) state.players.delete(id);
}
