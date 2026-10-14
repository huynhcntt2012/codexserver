const colors = [
  '#9ce6a0',
  '#ffbd79',
  '#b5a5ee',
  '#f78eaa',
  '#80cfe5',
  '#ecdb8c',
  '#ccabcf',
  '#d5e1bd',
];

export function drawBoard(canvas, snapshot, localId, time) {
  const ctx = canvas.getContext('2d');
  const cell = 48;
  const rect = (x, y, w, h, color) => {
    ctx.fillStyle = color;
    ctx.fillRect(x, y, w, h);
  };
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  for (let y = 0; y < 13; y++)
    for (let x = 0; x < 15; x++) {
      const px = x * cell,
        py = y * cell;
      rect(px, py, cell, cell, (x + y) % 2 ? '#192e34' : '#1c3237');
      const tile =
        snapshot?.grid[y]?.[x] ??
        (x === 0 ||
        y === 0 ||
        x === 14 ||
        y === 12 ||
        (x % 2 === 0 && y % 2 === 0)
          ? 1
          : (x * 7 + y * 11) % 5 === 0
            ? 2
            : 0);
      if (tile === 1) {
        rect(px + 2, py + 2, 44, 44, '#345356');
        rect(px + 2, py + 2, 44, 6, '#587771');
        rect(px + 7, py + 16, 33, 3, '#294148');
        rect(px + 7, py + 35, 33, 3, '#294148');
        rect(px + 19, py + 8, 3, 8, '#294148');
      } else if (tile === 2) {
        rect(px + 5, py + 8, 38, 37, '#302b2b');
        rect(px + 5, py + 4, 38, 35, '#99694c');
        rect(px + 8, py + 7, 32, 4, '#d7a475');
        rect(px + 10, py + 14, 27, 20, '#785239');
        rect(px + 20, py + 10, 7, 29, '#bb8a5b');
      }
    }
  for (const f of snapshot?.flames || []) {
    rect(f.x * cell + 2, f.y * cell + 13, 44, 22, '#ef9365');
    rect(f.x * cell + 13, f.y * cell + 2, 22, 44, '#f8bd74');
    rect(f.x * cell + 17, f.y * cell + 17, 14, 14, '#fff1b9');
  }
  for (const b of snapshot?.bombs || []) {
    const x = b.x * cell,
      y = b.y * cell;
    rect(x + 10, y + 15, 30, 26, '#10171f');
    rect(x + 15, y + 11, 20, 31, '#10171f');
    rect(x + 15, y + 18, 9, 6, '#6d7183');
    rect(x + 28, y + 5, 4, 9, '#dcc89f');
    rect(
      x + 29,
      y + 3,
      6,
      6,
      Math.floor(time / 120) % 2 ? '#ffc779' : '#f16d64',
    );
  }
  for (const p of snapshot?.players || []) {
    const x = p.x * cell,
      y = p.y * cell;
    const color = colors[p.slot % 8];
    if (!p.alive) {
      rect(x + 14, y + 34, 22, 7, '#66807c');
      continue;
    }
    rect(x + 7, y + 39, 35, 5, '#0c1b22');
    if (p.id === localId) {
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.strokeRect(x + 3, y + 3, 42, 42);
      rect(x + 21, y, 6, 3, '#f6edc6');
    }
    rect(x + 10, y + 12, 29, 26, color);
    rect(x + 16, y + 6, 17, 8, color);
    rect(x + 7, y + 23, 5, 11, color);
    rect(x + 39, y + 23, 4, 11, color);
    rect(x + 15, y + 18, 24, 11, '#173442');
    rect(x + 29, y + 20, 6, 5, '#d8f0e9');
    rect(x + 11, y + 37, 9, 6, color);
    rect(x + 29, y + 37, 9, 6, color);
  }
}
