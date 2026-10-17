import { useEffect, useRef, useState } from 'react';
import Layout from '@/components/Layout';
import { Card, Empty, Loading, Modal, Phase } from '@/components/ui';
import { api } from '@/lib/api';
import { dateTime } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

type Art = {
  floor: string;
  wall: string;
  crate: string;
  bomb: string;
  fx: string;
};

type MapDef = {
  id: string;
  name: string;
  tier: string;
  region: string;
  story: string;
  art: Art;
  layout: string[];
};

type GameMap = MapDef & {
  columns: number;
  rows: number;
  status: string;
  revision: number;
  updated_by: string;
  updated_at: string;
};

type Template = {
  template: MapDef;
  art: Record<keyof Art, string[]>;
  tiers: string[];
};

type Check = {
  ok: boolean;
  errors: string[];
  warnings: string[];
  layout: string[];
};

// Approximate floor colours of the game's tile sets, for the admin preview only.
const FLOOR: Record<string, string> = {
  grass: '#8acd65',
  sand: '#f1c878',
  snow: '#9fdcf7',
  lava: '#a8442c',
  pastry: '#f9c7a6',
  forest: '#93d9af',
  harbor: '#7edcf1',
  station: '#c8b4fa',
  clock: '#e7c48c',
  crystal: '#b9abff',
  market: '#e0a7dd',
  sky: '#91e1ee',
  volcano: '#ef8d7f',
  star: '#aab9f8',
  factory: '#b4ddc5',
  moon: '#bbb9f4',
};

/** The editable JSON for a map: exactly the template's fields, nothing server-made. */
function toJson(map: MapDef): string {
  const { id, name, tier, region, story, art, layout } = map;
  return JSON.stringify(
    { id, name, tier, region, story, art, layout },
    null,
    2,
  );
}

function corners(width: number, height: number): [number, number][] {
  return [
    [1, 1],
    [width - 2, 1],
    [width - 2, height - 2],
    [1, height - 2],
  ];
}

function seats(width: number, height: number): [number, number][] {
  const midX = (width - 1) / 2;
  const midY = (height - 1) / 2;
  return [
    [midX, 1],
    [midX, height - 2],
    [1, midY],
    [width - 2, midY],
  ];
}

/** Grid preview: walls, crates, floor colour, start corners (1–4) and extra online seats. */
function MapPreview({
  layout,
  floor,
  cell = 18,
}: {
  layout: string[];
  floor: string;
  cell?: number;
}) {
  const ref = useRef<HTMLCanvasElement>(null);
  const height = layout.length;
  const width = layout[0]?.length ?? 0;
  useEffect(() => {
    const ctx = ref.current?.getContext('2d');
    if (!ctx) return;
    ctx.clearRect(0, 0, width * cell, height * cell);
    layout.forEach((row, y) =>
      [...row].forEach((ch, x) => {
        ctx.fillStyle =
          ch === '#'
            ? '#6b7a8c'
            : ch === 'C'
              ? '#b9773e'
              : (FLOOR[floor] ?? '#ddd');
        ctx.fillRect(x * cell, y * cell, cell, cell);
        ctx.strokeStyle = 'rgba(0,0,0,0.15)';
        ctx.strokeRect(x * cell + 0.5, y * cell + 0.5, cell - 1, cell - 1);
      }),
    );
    if (width < 5 || height < 5) return;
    ctx.font = `bold ${Math.round(cell * 0.7)}px sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    corners(width, height).forEach(([x, y], i) => {
      ctx.fillStyle = '#1d78bd';
      ctx.beginPath();
      ctx.arc((x + 0.5) * cell, (y + 0.5) * cell, cell * 0.42, 0, Math.PI * 2);
      ctx.fill();
      ctx.fillStyle = '#fff';
      ctx.fillText(String(i + 1), (x + 0.5) * cell, (y + 0.55) * cell);
    });
    seats(width, height).forEach(([x, y]) => {
      ctx.strokeStyle = '#1d78bd';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.arc((x + 0.5) * cell, (y + 0.5) * cell, cell * 0.3, 0, Math.PI * 2);
      ctx.stroke();
      ctx.lineWidth = 1;
    });
  }, [layout, floor, cell, width, height]);
  return (
    <canvas
      ref={ref}
      width={width * cell}
      height={height * cell}
      className="map-preview"
      aria-label={`Bản đồ ${width}×${height}`}
    />
  );
}

function download(name: string, text: string) {
  const url = URL.createObjectURL(
    new Blob([text], { type: 'application/json' }),
  );
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.click();
  URL.revokeObjectURL(url);
}

export default function Maps() {
  const { can, toast } = useSession();
  const list = useLoad(
    () => api<{ maps: GameMap[]; builtin: string[] }>('/maps'),
    [],
  );
  const template = useLoad(() => api<Template>('/maps/template'), []);
  const [editing, setEditing] = useState<{
    text: string;
    existing: boolean;
  } | null>(null);
  const [result, setResult] = useState<Check | null>(null);
  const [busy, setBusy] = useState(false);

  function parse(): MapDef | null {
    if (!editing) return null;
    try {
      return JSON.parse(editing.text) as MapDef;
    } catch (reason) {
      setResult({
        ok: false,
        errors: [`JSON chưa đúng cú pháp: ${(reason as Error).message}`],
        warnings: [],
        layout: [],
      });
      return null;
    }
  }

  async function validate(): Promise<MapDef | null> {
    const body = parse();
    if (!body) return null;
    setBusy(true);
    try {
      const checked = await api<Check>('/maps/validate', {
        method: 'POST',
        body,
      });
      setResult(checked);
      return checked.ok ? body : null;
    } catch (reason) {
      setResult({
        ok: false,
        errors: [(reason as Error).message],
        warnings: [],
        layout: [],
      });
      return null;
    } finally {
      setBusy(false);
    }
  }

  async function save() {
    if (!editing) return;
    const body = await validate();
    if (!body) return;
    setBusy(true);
    try {
      if (editing.existing)
        await api(`/maps/${body.id}`, { method: 'PUT', body });
      else await api('/maps', { method: 'POST', body });
      toast(
        editing.existing
          ? 'Đã lưu bản đồ (tăng phiên bản)'
          : 'Đã tạo bản đồ (bản nháp)',
      );
      setEditing(null);
      setResult(null);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    } finally {
      setBusy(false);
    }
  }

  async function setStatus(map: GameMap, action: 'publish' | 'hide') {
    try {
      await api(`/maps/${map.id}/${action}`, { method: 'POST' });
      toast(
        action === 'publish'
          ? 'Đã phát hành: người chơi thấy bản đồ ở lần làm mới sảnh tới'
          : 'Đã ẩn bản đồ',
      );
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  function open(text: string, existing: boolean) {
    setResult(null);
    setEditing({ text, existing });
  }

  const draft = (() => {
    try {
      return editing ? (JSON.parse(editing.text) as MapDef) : null;
    } catch {
      return null;
    }
  })();
  const previewLayout =
    result?.ok && result.layout.length ? result.layout : draft?.layout;

  return (
    <Layout
      title="Bản đồ"
      subtitle="Thêm bản đồ bằng file JSON theo mẫu: kiểm tra, lưu nháp, phát hành cho người chơi."
      actions={
        can('liveops') &&
        template.data && (
          <div className="toolbar">
            <button
              className="btn secondary"
              onClick={() =>
                download('map-template.json', toJson(template.data!.template))
              }
            >
              ⬇ Tải template
            </button>
            <button
              className="btn warn"
              onClick={() => open(toJson(template.data!.template), false)}
            >
              + Bản đồ mới
            </button>
          </div>
        )
      }
    >
      <Card title="Cách thêm bản đồ">
        <ol className="steps">
          <li>
            Tải template, sửa <code>id</code>, <code>name</code>,{' '}
            <code>tier</code>, <code>art</code> và <code>layout</code> (
            <code>#</code> tường, <code>C</code> thùng, <code>.</code> ô trống).
          </li>
          <li>
            Bấm <b>Kiểm tra</b>: server báo lỗi cụ thể (kích thước lẻ 11–21 ×
            9–17, viền tường, 4 góc xuất phát, đường thoát khi đặt bom, các góc
            gặp được nhau, ảnh có trong game).
          </li>
          <li>
            <b>Lưu</b> tạo bản nháp. <b>Phát hành</b> để bản đồ xuất hiện ở
            sảnh, Tạo phòng và Luyện tập của app PC; <b>Ẩn</b> để rút lại (phòng
            đang chơi không bị ảnh hưởng).
          </li>
        </ol>
        {list.data && (
          <p className="spark">
            {list.data.builtin.length} bản đồ có sẵn trong game (không dùng lại
            id): {list.data.builtin.join(', ')}.
          </p>
        )}
      </Card>
      <Card
        title={
          list.data ? `${list.data.maps.length} bản đồ do admin thêm` : 'Bản đồ'
        }
      >
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.maps.length === 0 ? (
          <Empty title="Chưa có bản đồ nào">
            Tải template rồi bấm “+ Bản đồ mới”.
          </Empty>
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Bản đồ</th>
                  <th>Xem trước</th>
                  <th>Kích thước</th>
                  <th>Độ khó</th>
                  <th>Trạng thái</th>
                  <th>Phiên bản</th>
                  <th>Cập nhật</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {list.data.maps.map((map) => (
                  <tr key={map.id}>
                    <td>
                      <b>{map.name}</b>
                      <div className="spark">
                        {map.id}
                        {map.region ? ` · ${map.region}` : ''}
                      </div>
                    </td>
                    <td>
                      <MapPreview
                        layout={map.layout}
                        floor={map.art.floor}
                        cell={6}
                      />
                    </td>
                    <td>
                      {map.columns}×{map.rows}
                    </td>
                    <td>{map.tier}</td>
                    <td>
                      <Phase value={map.status} />
                    </td>
                    <td>v{map.revision}</td>
                    <td className="spark">
                      {map.updated_by}
                      <br />
                      {dateTime(map.updated_at)}
                    </td>
                    <td>
                      {can('liveops') && (
                        <div className="toolbar">
                          <button
                            className="btn small secondary"
                            onClick={() => open(toJson(map), true)}
                          >
                            Sửa
                          </button>
                          <button
                            className="btn small ghost"
                            onClick={() =>
                              download(`${map.id}.json`, toJson(map))
                            }
                          >
                            JSON
                          </button>
                          {map.status === 'published' ? (
                            <button
                              className="btn small ghost"
                              onClick={() => setStatus(map, 'hide')}
                            >
                              Ẩn
                            </button>
                          ) : (
                            <button
                              className="btn small"
                              onClick={() => setStatus(map, 'publish')}
                            >
                              Phát hành
                            </button>
                          )}
                        </div>
                      )}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </Card>
      {editing && (
        <Modal
          title={editing.existing ? 'Sửa bản đồ' : 'Bản đồ mới'}
          onClose={() => setEditing(null)}
          wide
        >
          <div className="map-editor">
            <div>
              <textarea
                className="input mono"
                rows={26}
                spellCheck={false}
                aria-label="JSON bản đồ"
                value={editing.text}
                onChange={(e) => {
                  setEditing({ ...editing, text: e.target.value });
                  setResult(null);
                }}
              />
              <div className="toolbar">
                <label className="btn small ghost upload">
                  Nạp file .json
                  <input
                    type="file"
                    accept="application/json,.json"
                    aria-label="Nạp file JSON bản đồ"
                    onChange={async (e) => {
                      const file = e.target.files?.[0];
                      e.target.value = '';
                      if (file) open(await file.text(), editing.existing);
                    }}
                  />
                </label>
                {template.data && (
                  <span className="spark">
                    floor: {template.data.art.floor.join(', ')} · wall:{' '}
                    {template.data.art.wall.join(', ')} · crate:{' '}
                    {template.data.art.crate.join(', ')} · bomb:{' '}
                    {template.data.art.bomb.join(', ')} · fx:{' '}
                    {template.data.art.fx.join(', ')}
                  </span>
                )}
              </div>
            </div>
            <div>
              {previewLayout && previewLayout.length > 0 ? (
                <MapPreview
                  layout={previewLayout}
                  floor={draft?.art?.floor ?? 'sand'}
                />
              ) : (
                <div className="empty">Xem trước hiện khi JSON hợp lệ.</div>
              )}
              <p className="spark">
                Số 1–4: góc xuất phát (Luyện tập và online). Vòng tròn: 4 ghế
                online thêm. Màu nền gần đúng; trong game dùng ảnh thật.
              </p>
              {result && (
                <div
                  className={`notice${result.ok ? ' info' : ''}`}
                  role="status"
                >
                  {result.ok ? '✅ Bản đồ hợp lệ.' : '❌ Chưa hợp lệ:'}
                  <ul>
                    {result.errors.map((e) => (
                      <li key={e}>{e}</li>
                    ))}
                    {result.warnings.map((w) => (
                      <li key={w}>⚠️ {w}</li>
                    ))}
                  </ul>
                </div>
              )}
            </div>
          </div>
          <div className="modal-actions">
            <button
              className="btn secondary"
              disabled={busy}
              onClick={validate}
            >
              Kiểm tra
            </button>
            <button className="btn" disabled={busy} onClick={save}>
              {editing.existing ? 'Lưu thay đổi' : 'Lưu bản nháp'}
            </button>
          </div>
        </Modal>
      )}
    </Layout>
  );
}
