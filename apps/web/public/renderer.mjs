const mascots = ['bong', 'may', 'la', 'nang'].map((name) => {
  const image = new Image();
  image.src = `/art/${name}.svg`;
  return image;
});

export function drawBoard(canvas, snapshot, localId, time, selected = null) {
  const ctx = canvas.getContext('2d');
  const cell = 48;
  const round = (x, y, w, h, radius, color) => {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, radius);
    ctx.fill();
  };
  const bubble = (x, y, radius, color) => {
    ctx.beginPath();
    ctx.arc(x, y, radius, 0, Math.PI * 2);
    ctx.fillStyle = color;
    ctx.fill();
    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2;
    ctx.stroke();
    ctx.beginPath();
    ctx.arc(x - radius * 0.3, y - radius * 0.35, radius * 0.22, 0, Math.PI * 2);
    ctx.fillStyle = '#f2ffff';
    ctx.fill();
  };
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  for (let y = 0; y < 13; y++)
    for (let x = 0; x < 15; x++) {
      const px = x * cell,
        py = y * cell;
      round(px, py, cell, cell, 4, (x + y) % 2 ? '#d7efc5' : '#e7f8d7');
      const tile =
        snapshot?.grid[y]?.[x] ??
        (x === 0 ||
        y === 0 ||
        x === 14 ||
        y === 12 ||
        (x % 2 === 0 && y % 2 === 0)
          ? 1
          : 0);
      if (tile === 1) {
        round(px + 4, py + 5, 40, 39, 10, '#90b0c1');
        round(px + 4, py + 3, 40, 31, 10, '#bdd6e2');
      } else if (tile === 2) {
        round(px + 5, py + 5, 38, 39, 9, '#c69758');
        round(px + 5, py + 3, 38, 13, 8, '#f5d699');
        ctx.strokeStyle = '#fff0ce';
        ctx.lineWidth = 2;
        ctx.beginPath();
        ctx.moveTo(px + 9, py + 17);
        ctx.lineTo(px + 31, py + 31);
        ctx.stroke();
      }
    }
  for (const f of snapshot?.flames || []) {
    round(f.x * cell + 1, f.y * cell + 1, 46, 46, 13, '#a1e6ed');
    bubble(f.x * cell + 24, f.y * cell + 24, 17, '#bef6fa');
  }
  for (const b of snapshot?.bombs || [])
    bubble(
      b.x * cell + 24,
      b.y * cell + 24,
      18 + Math.sin(time / 130),
      '#69d6ed',
    );
  for (const p of snapshot?.players || []) {
    const x = p.x * cell,
      y = p.y * cell;
    if (!p.alive) {
      round(x + 15, y + 34, 18, 6, 3, '#98b4ad');
      continue;
    }
    if (p.id === localId) {
      ctx.strokeStyle = '#225470';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.roundRect(x + 2, y + 2, 44, 44, 12);
      ctx.stroke();
    }
    const avatar =
      mascots[p.id === localId && selected !== null ? selected : p.slot % 4];
    if (avatar.complete && avatar.naturalWidth)
      ctx.drawImage(avatar, x + 5, y - 6, 38, 50);
  }
}
