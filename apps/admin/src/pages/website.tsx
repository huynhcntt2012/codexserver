import { useState } from 'react';
import Layout from '@/components/Layout';
import { Card, Empty, Field, Loading, Modal, Phase } from '@/components/ui';
import { api, upload } from '@/lib/api';
import { dateTime, fromLocalInput, number, toLocalInput } from '@/lib/format';
import { useLoad, useSession } from '@/lib/session';

// Website CMS for the promotion site at / (docs/PORTAL.md). Everything is
// plain text: the site sets it with textContent, the API strips control characters.

const CATEGORIES = ['Cập nhật', 'Sự kiện', 'Hướng dẫn'] as const;
// Art shipped with the web image; uploads use the PNG asset store instead.
const SITE_IMAGES = [
  'gameplay-online',
  'gameplay-practice',
  'gameplay-friends',
  'gameplay-moon',
  'gameplay-pastry',
  'news-event',
  'news-invite',
  'news-maps',
].map((name) => `/img/${name}.webp`);

type News = {
  id: string;
  slug: string;
  title: string;
  category: string;
  excerpt: string;
  body: string[];
  image: string;
  pinned: boolean;
  status: string;
  phase: string;
  publish_at: string;
  updated_by: string;
  updated_at: string;
};

type Draft = {
  id: string | null;
  slug: string;
  title: string;
  category: string;
  excerpt: string;
  body: string;
  image: string;
  pinned: boolean;
  publish_at: string;
};

type Hero = {
  headline: string;
  headline_accent: string;
  subline: string;
  cta_download: string;
  cta_demo: string;
};

type Release = {
  version?: string;
  fileName?: string;
  fileSizeBytes?: number | null;
  sha256?: string;
  publishedAt?: string;
  notes?: string;
  downloadUrl?: string;
};

const HERO_FIELDS: [keyof Hero, string, number, string][] = [
  ['headline', 'Tiêu đề', 40, 'Dòng chữ lớn đầu trang'],
  ['headline_accent', 'Tiêu đề phụ (màu nhấn)', 60, 'Có thể để trống'],
  ['subline', 'Dòng mô tả (ruy băng)', 120, 'Có thể để trống'],
  ['cta_download', 'Nút tải game', 24, 'Dẫn tới trang Tải game'],
  ['cta_demo', 'Nút chơi demo', 24, 'Mở bản Web /practice/'],
];

function slugify(text: string): string {
  return text
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/gi, 'd')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 80);
}

function size(bytes: number | null | undefined): string {
  if (bytes === null || bytes === undefined) return '—';
  if (bytes < 1024) return `${bytes} B`;
  return bytes >= 1048576
    ? `${(bytes / 1048576).toFixed(1)} MB`
    : `${Math.round(bytes / 1024)} KB`;
}

export default function Website() {
  const [tab, setTab] = useState('news');
  return (
    <Layout
      title="Website"
      subtitle="Tin tức, banner trang chủ và bản tải của trang quảng bá boom.sunifactory.com."
      actions={
        <a className="btn secondary" href="/" target="_blank" rel="noopener">
          Mở website ↗
        </a>
      }
    >
      <div className="tabs">
        {[
          ['news', 'Tin tức'],
          ['hero', 'Banner trang chủ'],
          ['downloads', 'Bản tải'],
        ].map(([key, label]) => (
          <button
            key={key}
            className={tab === key ? 'active' : ''}
            onClick={() => setTab(key)}
          >
            {label}
          </button>
        ))}
      </div>
      {tab === 'news' && <NewsManager />}
      {tab === 'hero' && <HeroEditor />}
      {tab === 'downloads' && <Downloads />}
    </Layout>
  );
}

function NewsManager() {
  const { can, toast } = useSession();
  const editor = can('liveops');
  const [editing, setEditing] = useState<Draft | null>(null);
  const [busy, setBusy] = useState(false);
  const list = useLoad(() => api<{ news: News[] }>('/website/news'));

  function open(post: News | null) {
    setEditing(
      post
        ? {
            ...post,
            body: post.body.join('\n\n'),
            publish_at: toLocalInput(post.publish_at),
          }
        : {
            id: null,
            slug: '',
            title: '',
            category: CATEGORIES[0],
            excerpt: '',
            body: '',
            image: SITE_IMAGES[0],
            pinned: false,
            publish_at: toLocalInput(new Date()),
          },
    );
  }

  async function save() {
    if (!editing) return;
    setBusy(true);
    const body = {
      slug: editing.slug,
      title: editing.title,
      category: editing.category,
      excerpt: editing.excerpt,
      // Blank lines separate paragraphs; the site renders each as a <p>.
      body: editing.body
        .split(/\n\s*\n/)
        .map((p) => p.trim())
        .filter(Boolean),
      image: editing.image,
      pinned: editing.pinned,
      publish_at: fromLocalInput(editing.publish_at),
    };
    try {
      await api(editing.id ? `/website/news/${editing.id}` : '/website/news', {
        method: editing.id ? 'PUT' : 'POST',
        body,
      });
      toast(editing.id ? 'Đã lưu bài viết' : 'Đã tạo bản nháp');
      setEditing(null);
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    } finally {
      setBusy(false);
    }
  }

  async function act(post: News, action: 'publish' | 'unpublish') {
    try {
      await api(`/website/news/${post.id}/${action}`, { method: 'POST' });
      toast(action === 'publish' ? 'Đã đăng bài' : 'Đã gỡ về bản nháp');
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function remove(post: News) {
    if (!confirm(`Xóa vĩnh viễn bài "${post.title}"?`)) return;
    try {
      await api(`/website/news/${post.id}`, { method: 'DELETE' });
      toast('Đã xóa bài viết');
      list.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  async function uploadImage(file: File) {
    if (!editing) return;
    try {
      const saved = await upload<{ url: string }>('/website/images', file);
      setEditing({ ...editing, image: saved.url });
      toast('Đã tải ảnh lên');
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  const paragraphs = editing
    ? editing.body.split(/\n\s*\n/).filter((p) => p.trim()).length
    : 0;
  const valid =
    editing &&
    /^[a-z0-9]+(-[a-z0-9]+)*$/.test(editing.slug) &&
    editing.slug.length >= 3 &&
    editing.title.trim().length >= 3 &&
    paragraphs > 0 &&
    editing.publish_at;

  return (
    <>
      <div className="notice info">
        Bài đã đăng hiện ở trang Tin tức và trang chủ website (tối đa 1 phút
        cache). Bài có ngày đăng trong tương lai sẽ tự hiện khi tới giờ. Bài
        ghim luôn đứng đầu.
      </div>
      <Card
        title="Bài viết"
        action={
          editor && (
            <button className="btn warn" onClick={() => open(null)}>
              + Viết bài
            </button>
          )
        }
      >
        {!list.data ? (
          <Loading error={list.error} />
        ) : list.data.news.length === 0 ? (
          <Empty title="Chưa có bài viết" />
        ) : (
          <div className="table-wrap">
            <table>
              <thead>
                <tr>
                  <th>Ảnh</th>
                  <th>Bài viết</th>
                  <th>Danh mục</th>
                  <th>Ngày đăng</th>
                  <th>Trạng thái</th>
                  <th />
                </tr>
              </thead>
              <tbody>
                {list.data.news.map((post) => (
                  <tr key={post.id}>
                    <td>
                      <img
                        className="news-thumb"
                        src={post.image}
                        alt=""
                        loading="lazy"
                      />
                    </td>
                    <td>
                      <b>
                        {post.pinned && '📌 '}
                        {post.title}
                      </b>
                      <div className="spark">
                        /{post.slug} · sửa bởi {post.updated_by}
                      </div>
                    </td>
                    <td>{post.category}</td>
                    <td className="spark">{dateTime(post.publish_at)}</td>
                    <td>
                      <Phase value={post.phase} />
                    </td>
                    <td>
                      <div className="toolbar">
                        {post.phase === 'published' && (
                          <a
                            className="btn small ghost"
                            href={`/news/post/?slug=${encodeURIComponent(post.slug)}`}
                            target="_blank"
                            rel="noopener"
                          >
                            Xem
                          </a>
                        )}
                        <button
                          className="btn small secondary"
                          onClick={() => open(post)}
                        >
                          {editor ? 'Sửa' : 'Chi tiết'}
                        </button>
                        {editor &&
                          (post.status === 'published' ? (
                            <button
                              className="btn small ghost"
                              onClick={() => act(post, 'unpublish')}
                            >
                              Gỡ
                            </button>
                          ) : (
                            <button
                              className="btn small success"
                              onClick={() => act(post, 'publish')}
                            >
                              Đăng
                            </button>
                          ))}
                        {editor && (
                          <button
                            className="btn small danger"
                            onClick={() => remove(post)}
                          >
                            Xóa
                          </button>
                        )}
                      </div>
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
          title={editing.id ? 'Sửa bài viết' : 'Viết bài mới'}
          onClose={() => setEditing(null)}
          wide
        >
          <fieldset className="plain" disabled={!editor}>
            <div className="form cols">
              <Field label="Tiêu đề" full>
                <input
                  className="input"
                  maxLength={120}
                  value={editing.title}
                  onChange={(e) =>
                    setEditing({
                      ...editing,
                      title: e.target.value,
                      slug: editing.id ? editing.slug : slugify(e.target.value),
                    })
                  }
                />
              </Field>
              <Field
                label="Đường dẫn (slug)"
                hint="Chữ thường, số và dấu gạch ngang"
              >
                <input
                  className="input"
                  maxLength={80}
                  value={editing.slug}
                  onChange={(e) =>
                    setEditing({ ...editing, slug: slugify(e.target.value) })
                  }
                />
              </Field>
              <Field label="Danh mục">
                <select
                  className="input"
                  value={editing.category}
                  onChange={(e) =>
                    setEditing({ ...editing, category: e.target.value })
                  }
                >
                  {CATEGORIES.map((c) => (
                    <option key={c}>{c}</option>
                  ))}
                </select>
              </Field>
              <Field label="Ngày đăng">
                <input
                  className="input"
                  type="datetime-local"
                  value={editing.publish_at}
                  onChange={(e) =>
                    setEditing({ ...editing, publish_at: e.target.value })
                  }
                />
              </Field>
              <div className="field">
                <span>Ghim</span>
                <label className="check">
                  <input
                    type="checkbox"
                    checked={editing.pinned}
                    onChange={(e) =>
                      setEditing({ ...editing, pinned: e.target.checked })
                    }
                  />
                  Ghim lên đầu danh sách
                </label>
              </div>
              <Field
                label="Tóm tắt"
                full
                hint="Hiện trên thẻ tin (≤ 300 ký tự)"
              >
                <textarea
                  className="input"
                  rows={2}
                  maxLength={300}
                  value={editing.excerpt}
                  onChange={(e) =>
                    setEditing({ ...editing, excerpt: e.target.value })
                  }
                />
              </Field>
              <Field
                label="Nội dung"
                full
                hint={`Chữ thuần, cách đoạn bằng một dòng trống · ${paragraphs} đoạn`}
              >
                <textarea
                  className="input"
                  rows={9}
                  value={editing.body}
                  onChange={(e) =>
                    setEditing({ ...editing, body: e.target.value })
                  }
                />
              </Field>
              <div className="field full">
                <span>Ảnh bìa</span>
                <div className="image-pick">
                  <img src={editing.image} alt="Ảnh bìa đang chọn" />
                  <div className="form">
                    <select
                      className="input"
                      aria-label="Ảnh có sẵn"
                      value={
                        SITE_IMAGES.includes(editing.image) ? editing.image : ''
                      }
                      onChange={(e) =>
                        e.target.value &&
                        setEditing({ ...editing, image: e.target.value })
                      }
                    >
                      {!SITE_IMAGES.includes(editing.image) && (
                        <option value="">Ảnh đã tải lên</option>
                      )}
                      {SITE_IMAGES.map((src) => (
                        <option key={src} value={src}>
                          {src.split('/').pop()}
                        </option>
                      ))}
                    </select>
                    {editor && (
                      <label className="btn small secondary">
                        Tải ảnh PNG…
                        <input
                          type="file"
                          accept="image/png"
                          hidden
                          onChange={(e) => {
                            const file = e.target.files?.[0];
                            if (file) uploadImage(file);
                            e.target.value = '';
                          }}
                        />
                      </label>
                    )}
                    <small className="spark">
                      PNG 16–2048 px, ≤ 10 MB; nên dùng tỉ lệ 16:9.
                    </small>
                  </div>
                </div>
              </div>
            </div>
          </fieldset>
          <div className="modal-actions">
            <button className="btn ghost" onClick={() => setEditing(null)}>
              {editor ? 'Hủy' : 'Đóng'}
            </button>
            {editor && (
              <button className="btn" onClick={save} disabled={!valid || busy}>
                {editing.id ? 'Lưu bài viết' : 'Tạo bản nháp'}
              </button>
            )}
          </div>
        </Modal>
      )}
    </>
  );
}

function HeroEditor() {
  const { can, toast } = useSession();
  const editor = can('liveops');
  const [draft, setDraft] = useState<Hero | null>(null);
  const site = useLoad(() =>
    api<{
      hero: Hero;
      defaults: Hero;
      updated_by: string | null;
      updated_at: string | null;
    }>('/website/site').then((data) => {
      setDraft(data.hero);
      return data;
    }),
  );

  async function save() {
    if (!draft) return;
    try {
      await api('/website/site', { method: 'PUT', body: draft });
      toast('Đã lưu banner trang chủ');
      site.reload();
    } catch (reason) {
      toast((reason as Error).message, true);
    }
  }

  if (!site.data || !draft) return <Loading error={site.error} />;
  const valid =
    draft.headline.trim().length >= 2 &&
    draft.cta_download.trim().length >= 2 &&
    draft.cta_demo.trim().length >= 2;
  return (
    <div className="grid two">
      <Card
        title="Nội dung banner"
        action={
          site.data.updated_by && (
            <span className="spark">
              Sửa bởi {site.data.updated_by} · {dateTime(site.data.updated_at)}
            </span>
          )
        }
      >
        <fieldset className="plain" disabled={!editor}>
          <div className="form">
            {HERO_FIELDS.map(([key, label, max, hint]) => (
              <Field key={key} label={label} hint={`${hint} · ≤ ${max} ký tự`}>
                <input
                  className="input"
                  aria-label={label}
                  maxLength={max}
                  value={draft[key]}
                  onChange={(e) =>
                    setDraft({ ...draft, [key]: e.target.value })
                  }
                />
              </Field>
            ))}
          </div>
        </fieldset>
        {editor && (
          <div className="modal-actions">
            <button
              className="btn ghost"
              onClick={() => setDraft(site.data!.defaults)}
            >
              Về mặc định
            </button>
            <button className="btn" onClick={save} disabled={!valid}>
              Lưu banner
            </button>
          </div>
        )}
      </Card>
      <Card title="Xem trước">
        <div className="hero-preview" aria-label="Xem trước banner">
          <b>{draft.headline}</b>
          {draft.headline_accent && <em>{draft.headline_accent}</em>}
          {draft.subline && <span className="ribbon">{draft.subline}</span>}
          <div className="toolbar">
            <span className="btn warn">{draft.cta_download}</span>
            <span className="btn">{draft.cta_demo}</span>
          </div>
        </div>
      </Card>
    </div>
  );
}

function Downloads() {
  const data = useLoad(() =>
    api<{
      configured: boolean;
      latest: Release | null;
      history: Release[];
      files: { name: string; size: number; modified_at: string }[];
    }>('/website/releases'),
  );
  if (!data.data) return <Loading error={data.error} />;
  const { configured, latest, history, files } = data.data;
  return (
    <>
      <div className="notice info">
        <span>
          Chỉ xem. Phát hành bản mới bằng{' '}
          <code>python3 scripts/publish-release.py file.zip --version X</code>{' '}
          trên máy chủ: script ghi <code>latest.json</code> và{' '}
          <code>history.json</code>, website đổi nút tải ngay, không cần build
          lại.
        </span>
      </div>
      {!configured ? (
        <Empty title="API chưa được gắn thư mục bản phát hành (RELEASES_DIR)" />
      ) : (
        <div className="grid two">
          <Card title="Bản đang tải (latest.json)">
            {!latest ? (
              <Empty title="Chưa có bản phát hành">
                Website đang hiện “Đang cập nhật bản tải”.
              </Empty>
            ) : (
              <dl className="facts">
                <dt>Phiên bản</dt>
                <dd>{latest.version ?? '—'}</dd>
                <dt>Tệp</dt>
                <dd>{latest.fileName ?? '—'}</dd>
                <dt>Dung lượng</dt>
                <dd>{size(latest.fileSizeBytes)}</dd>
                <dt>Phát hành</dt>
                <dd>{dateTime(latest.publishedAt)}</dd>
                <dt>SHA-256</dt>
                <dd className="mono">{latest.sha256 ?? '—'}</dd>
                <dt>Ghi chú</dt>
                <dd>{latest.notes || '—'}</dd>
              </dl>
            )}
          </Card>
          <Card title={`Tệp ZIP trên máy chủ (${number(files.length)})`}>
            {files.length === 0 ? (
              <Empty title="Chưa có tệp ZIP" />
            ) : (
              <div className="list">
                {files.map((f) => (
                  <div key={f.name}>
                    <span className="grow">{f.name}</span>
                    <span className="spark">
                      {size(f.size)} · {dateTime(f.modified_at)}
                    </span>
                  </div>
                ))}
              </div>
            )}
          </Card>
        </div>
      )}
      {configured && (
        <Card title="Lịch sử phát hành">
          {history.length === 0 ? (
            <Empty title="Chưa có lịch sử">
              Lịch sử được ghi từ lần chạy publish-release.py tiếp theo.
            </Empty>
          ) : (
            <div className="table-wrap">
              <table>
                <thead>
                  <tr>
                    <th>Phiên bản</th>
                    <th>Ngày</th>
                    <th>Dung lượng</th>
                    <th>Ghi chú</th>
                  </tr>
                </thead>
                <tbody>
                  {history.map((r, i) => (
                    <tr key={`${r.version}-${i}`}>
                      <td>
                        <b>{r.version}</b>{' '}
                        {i === 0 && (
                          <span className="badge green">Mới nhất</span>
                        )}
                      </td>
                      <td className="spark">{dateTime(r.publishedAt)}</td>
                      <td>{size(r.fileSizeBytes)}</td>
                      <td>{r.notes || '—'}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </Card>
      )}
    </>
  );
}
