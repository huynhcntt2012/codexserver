// Presentation only. Never mutate a snapshot or send predicted coordinates.
const directions = { up: [0, -1], down: [0, 1], left: [-1, 0], right: [1, 0] };
export class MovementVisual {
  constructor() {
    this.clear();
  }
  clear() {
    this.positions = new Map();
    this.cue = null;
    this.round = null;
    this.lastTime = null;
  }
  intent(snapshot, id, action, time) {
    const p = snapshot?.players.find((p) => p.id === id);
    const d = directions[action];
    if (snapshot?.phase !== 'playing' || !p?.alive || !d) return;
    const x = p.x + d[0],
      y = p.y + d[1];
    if (
      snapshot.grid[y]?.[x] !== 0 ||
      snapshot.bombs.some((b) => b.x === x && b.y === y) ||
      snapshot.players.some(
        (other) =>
          other.id !== id && other.alive && other.x === x && other.y === y,
      )
    )
      return;
    // Do not refresh an unconfirmed cue indefinitely when packets are delayed.
    if (
      this.cue?.x === p.x &&
      this.cue?.y === p.y &&
      this.cue?.action === action
    )
      return;
    this.cue = { x: p.x, y: p.y, action, time, round: snapshot.round };
  }
  sample(snapshot, id, time) {
    if (!snapshot) {
      this.clear();
      return this.positions;
    }
    if (this.round !== snapshot.round || snapshot.phase !== 'playing') {
      this.positions.clear();
      this.cue = null;
    }
    this.round = snapshot.round;
    const dt =
      this.lastTime === null
        ? 1 / 60
        : Math.min(0.05, Math.max(0, (time - this.lastTime) / 1000));
    this.lastTime = time;
    const active = new Set();
    for (const p of snapshot.players) {
      active.add(p.id);
      let x = p.x,
        y = p.y;
      if (p.id === id && this.cue) {
        const c = this.cue;
        if (
          !p.alive ||
          c.round !== snapshot.round ||
          p.x !== c.x ||
          p.y !== c.y
        )
          this.cue = null;
        else if (time - c.time < 250) {
          const d = directions[c.action];
          // A small lean provides immediate feedback, never crosses a tile boundary.
          const amount = 0.25 * Math.min(1, Math.max(0, (time - c.time) / 50));
          x += d[0] * amount;
          y += d[1] * amount;
        }
      }
      const previous = this.positions.get(p.id) ?? { x: p.x, y: p.y };
      const distance = Math.hypot(x - previous.x, y - previous.y);
      const step = dt * (p.id === id ? 20 : 14);
      const snap = !p.alive || snapshot.phase !== 'playing' || distance > 2;
      const ratio = snap || distance <= step ? 1 : step / distance;
      this.positions.set(p.id, {
        x: previous.x + (x - previous.x) * ratio,
        y: previous.y + (y - previous.y) * ratio,
      });
    }
    for (const key of this.positions.keys())
      if (!active.has(key)) this.positions.delete(key);
    return this.positions;
  }
}
