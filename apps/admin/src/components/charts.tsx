// Small SVG charts drawn from real series; no chart library needed.
import { shortDay } from '@/lib/format';

export type Point = { day: string; count: number };

export function LineChart({
  series,
  colors = ['#1f8fe5', '#ff9f43'],
  labels = [],
}: {
  series: Point[][];
  colors?: string[];
  labels?: string[];
}) {
  const width = 640;
  const height = 220;
  const pad = { left: 36, right: 12, top: 14, bottom: 26 };
  const days = series[0] ?? [];
  const max = Math.max(1, ...series.flat().map((p) => p.count));
  const top = Math.ceil(max / 4) * 4;
  const x = (i: number) =>
    pad.left +
    (i * (width - pad.left - pad.right)) / Math.max(1, days.length - 1);
  const y = (v: number) =>
    height - pad.bottom - (v * (height - pad.top - pad.bottom)) / top;
  const ticks = [0, top / 4, top / 2, (top * 3) / 4, top];
  const every = Math.max(1, Math.ceil(days.length / 7));
  return (
    <div>
      <svg
        className="chart"
        viewBox={`0 0 ${width} ${height}`}
        width="100%"
        role="img"
        aria-label={labels.join(', ')}
      >
        {ticks.map((t) => (
          <g key={t}>
            <line
              x1={pad.left}
              x2={width - pad.right}
              y1={y(t)}
              y2={y(t)}
              stroke="#e3ebf5"
            />
            <text x={pad.left - 8} y={y(t) + 4} textAnchor="end">
              {Math.round(t)}
            </text>
          </g>
        ))}
        {days.map((p, i) =>
          i % every === 0 ? (
            <text key={p.day} x={x(i)} y={height - 6} textAnchor="middle">
              {shortDay(p.day)}
            </text>
          ) : null,
        )}
        {series.map((points, s) => {
          const path = points
            .map((p, i) => `${i ? 'L' : 'M'}${x(i)},${y(p.count)}`)
            .join(' ');
          const area = `${path} L${x(points.length - 1)},${y(0)} L${x(0)},${y(0)} Z`;
          return (
            <g key={s}>
              {s === 0 && <path d={area} fill={colors[s]} opacity={0.12} />}
              <path d={path} fill="none" stroke={colors[s]} strokeWidth={2.5} />
              {points.map((p, i) => (
                <circle
                  key={p.day}
                  cx={x(i)}
                  cy={y(p.count)}
                  r={3}
                  fill={colors[s]}
                >
                  <title>{`${shortDay(p.day)}: ${p.count}`}</title>
                </circle>
              ))}
            </g>
          );
        })}
      </svg>
      {labels.length > 1 && (
        <div className="toolbar spark">
          {labels.map((label, i) => (
            <span key={label} className="check">
              <svg width="14" height="4" aria-hidden>
                <rect width="14" height="4" rx="2" fill={colors[i]} />
              </svg>
              {label}
            </span>
          ))}
        </div>
      )}
    </div>
  );
}

export function Donut({
  parts,
  center,
  caption,
}: {
  parts: { label: string; value: number; color: string }[];
  center: string;
  caption: string;
}) {
  const total = parts.reduce((sum, p) => sum + p.value, 0);
  const radius = 70;
  const length = 2 * Math.PI * radius;
  let offset = 0;
  return (
    <div className="grid halves">
      <svg viewBox="0 0 200 200" width="100%" role="img" aria-label={caption}>
        <circle
          cx="100"
          cy="100"
          r={radius}
          fill="none"
          stroke="#eef2f7"
          strokeWidth="26"
        />
        {total > 0 &&
          parts.map((p) => {
            const dash = (p.value / total) * length;
            const node = (
              <circle
                key={p.label}
                cx="100"
                cy="100"
                r={radius}
                fill="none"
                stroke={p.color}
                strokeWidth="26"
                strokeDasharray={`${dash} ${length - dash}`}
                strokeDashoffset={-offset}
                transform="rotate(-90 100 100)"
              />
            );
            offset += dash;
            return node;
          })}
        <text
          x="100"
          y="98"
          textAnchor="middle"
          fontSize="28"
          fontWeight="900"
          fill="#1d2b45"
        >
          {center}
        </text>
        <text x="100" y="120" textAnchor="middle" fontSize="12" fill="#6a7b96">
          {caption}
        </text>
      </svg>
      <div className="legend">
        {parts.map((p) => (
          <div key={p.label}>
            <svg width="12" height="12" aria-hidden>
              <circle cx="6" cy="6" r="6" fill={p.color} />
            </svg>
            {p.label}
            <span>
              {p.value}
              {total ? ` · ${Math.round((p.value / total) * 100)}%` : ''}
            </span>
          </div>
        ))}
      </div>
    </div>
  );
}

export function Bars({
  points,
  color = '#1f8fe5',
}: {
  points: Point[];
  color?: string;
}) {
  const width = 640;
  const height = 180;
  const max = Math.max(1, ...points.map((p) => p.count));
  const slot = (width - 20) / Math.max(1, points.length);
  return (
    <svg
      className="chart"
      viewBox={`0 0 ${width} ${height}`}
      width="100%"
      role="img"
    >
      {points.map((p, i) => {
        const h = (p.count / max) * (height - 40);
        return (
          <g key={p.day}>
            <rect
              x={10 + i * slot + slot * 0.18}
              y={height - 22 - h}
              width={slot * 0.64}
              height={Math.max(h, 1)}
              rx="4"
              fill={color}
            >
              <title>{`${shortDay(p.day)}: ${p.count}`}</title>
            </rect>
            {(points.length <= 14 || i % 2 === 0) && (
              <text
                x={10 + i * slot + slot / 2}
                y={height - 6}
                textAnchor="middle"
              >
                {shortDay(p.day)}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}
