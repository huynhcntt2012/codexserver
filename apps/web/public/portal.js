// BỤP BỤP! promotion website (docs/PORTAL.md). No framework, no inline code (CSP).
// Text from the API or JSON is always set with textContent, never as HTML.

const BASE = '/';
const API = '/api';
const RELEASE_URL = '/releases/latest.json';
const DEMO_URL = '/demo/';
const LOGIN_URL = '/demo/';

const ICON = {
  menu: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><path d="M4 7h16M4 12h16M4 17h16"/></svg>',
  download:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11m0 0-4.5-4.5M12 15l4.5-4.5M5 20h14"/></svg>',
  play: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M7 4.5v15l12.5-7.5z"/></svg>',
  windows:
    '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M3 5.2 10.4 4v7.3H3zm8.5-1.4L21 2.4v8.9h-9.5zM3 12.7h7.4V20L3 18.8zm8.5 0H21v8.9l-9.5-1.4z"/></svg>',
  globe:
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c3 3.2 3 14.8 0 18M12 3c-3 3.2-3 14.8 0 18"/></svg>',
  android:
    '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6 9h12v8a1.5 1.5 0 0 1-1.5 1.5H15V21h-2v-2.5h-2V21H9v-2.5H7.5A1.5 1.5 0 0 1 6 17zM4 9.5a1 1 0 0 1 2 0v5a1 1 0 0 1-2 0zm14 0a1 1 0 0 1 2 0v5a1 1 0 0 1-2 0zM6.2 8a5.8 5.8 0 0 1 11.6 0zM9.5 5.8a.7.7 0 1 0 0-.01zm5 0a.7.7 0 1 0 0-.01z"/></svg>',
  apple:
    '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M16.4 12.6c0-2.3 1.9-3.4 2-3.5-1.1-1.6-2.8-1.8-3.4-1.8-1.4-.2-2.8.8-3.5.8s-1.8-.8-3-.8C7 7.3 5.5 8.3 4.7 9.8c-1.7 2.9-.4 7.2 1.2 9.6.8 1.2 1.7 2.5 3 2.4 1.2 0 1.6-.8 3-.8s1.8.8 3 .8c1.3 0 2.1-1.2 2.9-2.4.9-1.3 1.3-2.6 1.3-2.7 0 0-2.6-1-2.7-4.1zM14.1 5.6c.6-.8 1.1-1.9 1-3-.9 0-2.1.6-2.7 1.4-.6.7-1.1 1.8-1 2.9 1 .1 2.1-.5 2.7-1.3z"/></svg>',
  home: '<svg viewBox="0 0 24 24"><path d="M12 3 2.5 11h2.8v9h5v-6h3.4v6h5v-9h2.8z"/></svg>',
  hero: '<svg viewBox="0 0 24 24"><circle cx="12" cy="8" r="4.5"/><path d="M3.5 21c.8-4.6 4.2-7 8.5-7s7.7 2.4 8.5 7z"/></svg>',
  map: '<svg viewBox="0 0 24 24"><path d="m3 6 6-2.5 6 2.5 6-2.5v14.5L15 20.5 9 18l-6 2.5zm6-.3v10.6l6 2.5V8.2z"/></svg>',
  gift: '<svg viewBox="0 0 24 24"><path d="M3 9h18v4H3zm1 5h7v7H4zm9 0h7v7h-7zM11 9h2v12h-2zM7.5 3.5C9.4 3.5 11 6 12 9 9 9 5 8.6 5 6c0-1.4 1-2.5 2.5-2.5zm9 0C18 3.5 19 4.6 19 6c0 2.6-4 3-7 3 1-3 2.6-5.5 4.5-5.5z"/></svg>',
};

const NAV = [
  ['', 'Trang chủ'],
  ['about/', 'Giới thiệu'],
  ['characters/', 'Nhân vật'],
  ['maps/', 'Bản đồ'],
  ['events/', 'Sự kiện'],
  ['rankings/', 'Bảng xếp hạng'],
  ['news/', 'Tin tức'],
  ['support/', 'Hỗ trợ'],
];
const TABS = [
  ['', 'Trang chủ', 'home'],
  ['characters/', 'Nhân vật', 'hero'],
  ['maps/', 'Bản đồ', 'map'],
  ['events/', 'Sự kiện', 'gift'],
];
const HERO_NAMES = {
  bombo: 'Bombo',
  mimi: 'Mimi',
  zin: 'Zin',
  lala: 'Lala',
  kai: 'Kai',
};

// ------------------------------------------------------------------ helpers

function el(tag, attrs = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(attrs)) {
    if (value === null || value === undefined || value === false) continue;
    if (key === 'class') node.className = value;
    else if (key === 'text') node.textContent = value;
    else if (key === 'icon') node.insertAdjacentHTML('afterbegin', ICON[value]);
    else if (key.startsWith('on')) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value === true ? '' : value);
  }
  for (const child of children.flat()) {
    if (child === null || child === undefined || child === false) continue;
    node.append(
      child instanceof Node ? child : document.createTextNode(String(child)),
    );
  }
  return node;
}

function img(src, alt = '', attrs = {}) {
  return el('img', { src, alt, loading: 'lazy', decoding: 'async', ...attrs });
}

async function getJSON(url) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 8000);
  try {
    const reply = await fetch(url, {
      signal: controller.signal,
      headers: { Accept: 'application/json' },
    });
    if (!reply.ok)
      throw Object.assign(new Error(`HTTP ${reply.status}`), {
        status: reply.status,
      });
    return await reply.json();
  } finally {
    clearTimeout(timer);
  }
}

const cache = new Map();
function load(url) {
  if (!cache.has(url)) cache.set(url, getJSON(url));
  return cache.get(url);
}

const gameData = () => load(BASE + 'data/game.json');
// News are edited in the Admin Portal (Website); data/news.json is the offline copy
// used only when the API cannot be reached.
const staticNews = () =>
  load(BASE + 'data/news.json').then((d) => sortNews(d.news));
const newsData = () =>
  load(`${API}/v1/public/news`)
    .then((d) => sortNews(d.news))
    .catch(staticNews);
async function postData(slug) {
  try {
    return await getJSON(`${API}/v1/public/news/${encodeURIComponent(slug)}`);
  } catch (error) {
    if (error.status === 404) return null;
    return (await staticNews()).find((n) => n.slug === slug) || null;
  }
}
const releaseData = () => load(RELEASE_URL).catch(() => null);

function sortNews(list) {
  return [...list].sort(
    (a, b) =>
      (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0) || b.date.localeCompare(a.date),
  );
}

function skeletons(target, count, height = 220) {
  target.replaceChildren(
    ...Array.from({ length: count }, () => {
      const box = el('div', { class: 'skeleton' });
      box.style.minHeight = `${height}px`;
      return box;
    }),
  );
}

function state(target, message, retry) {
  target.replaceChildren(
    el(
      'div',
      { class: 'state', role: 'status' },
      el('p', { text: message }),
      retry
        ? el('button', {
            class: 'btn btn-line btn-sm',
            type: 'button',
            onclick: retry,
            text: 'Thử lại',
          })
        : null,
    ),
  );
}

const dateFmt = new Intl.DateTimeFormat('vi-VN', {
  day: '2-digit',
  month: '2-digit',
  year: 'numeric',
});
const timeFmt = new Intl.DateTimeFormat('vi-VN', {
  day: '2-digit',
  month: '2-digit',
  hour: '2-digit',
  minute: '2-digit',
});
const formatDate = (iso) =>
  dateFmt.format(new Date(iso.length === 10 ? `${iso}T00:00:00` : iso));
const formatSize = (bytes) =>
  bytes >= 1048576
    ? `${(bytes / 1048576).toFixed(1)} MB`
    : `${Math.round(bytes / 1024)} KB`;

function categoryClass(category) {
  return (
    { 'Cập nhật': 'update', 'Sự kiện': 'event', 'Hướng dẫn': 'guide' }[
      category
    ] || ''
  );
}

// ------------------------------------------------------------------ chrome

function current(path) {
  const here = location.pathname.replace(/index\.html$/, '');
  const target = BASE + path;
  return path === '' ? here === BASE : here.startsWith(target);
}

function downloadButton(label, extra = 'btn-sun') {
  return el(
    'a',
    {
      class: `btn ${extra}`,
      href: BASE + 'download/',
      icon: 'download',
      'data-cta': 'download',
    },
    label,
  );
}

function renderHeader() {
  const header = document.querySelector('.site-header');
  if (!header) return;
  const drawer = el('div', {
    class: 'drawer',
    id: 'drawer',
    onclick: (e) => e.target === drawer && toggleDrawer(false),
  });
  const links = NAV.map(([path, label]) =>
    el('a', {
      href: BASE + path,
      'aria-current': current(path) ? 'page' : null,
      text: label,
    }),
  );
  drawer.append(
    el(
      'nav',
      { 'aria-label': 'Menu' },
      ...links.map((a) => a.cloneNode(true)),
      el('a', { class: 'btn btn-ghost', href: LOGIN_URL, text: 'Đăng nhập' }),
      downloadButton('Tải game'),
    ),
  );
  const menu = el('button', {
    class: 'menu-button',
    type: 'button',
    'aria-label': 'Mở menu',
    'aria-expanded': 'false',
    'aria-controls': 'drawer',
    icon: 'menu',
    onclick: () => toggleDrawer(true),
  });
  header.replaceChildren(
    el(
      'div',
      { class: 'wrap' },
      menu,
      el(
        'a',
        { class: 'logo', href: BASE, 'aria-label': 'BỤP BỤP! – Trang chủ' },
        el('img', {
          src: BASE + 'assets/ui/launch/logo_bupbup.png',
          alt: 'BỤP BỤP!',
          width: 165,
          height: 56,
        }),
      ),
      el('ul', { class: 'nav' }, ...links.map((a) => el('li', {}, a))),
      el(
        'div',
        { class: 'head-actions' },
        el('a', {
          class: 'btn btn-ghost btn-sm',
          href: LOGIN_URL,
          text: 'Đăng nhập',
        }),
        downloadButton('Tải game'),
      ),
    ),
  );
  document.body.append(drawer);
  document.addEventListener(
    'keydown',
    (e) => e.key === 'Escape' && toggleDrawer(false),
  );
}

function toggleDrawer(open) {
  const drawer = document.getElementById('drawer');
  if (!drawer) return;
  drawer.classList.toggle('open', open);
  document
    .querySelector('.menu-button')
    ?.setAttribute('aria-expanded', String(open));
  if (open) drawer.querySelector('a')?.focus();
}

function renderFooter() {
  const footer = document.querySelector('.site-footer');
  if (footer) {
    const list = (title, items) =>
      el(
        'div',
        {},
        el('h3', { text: title }),
        el(
          'ul',
          {},
          ...items.map(([href, label]) =>
            el('li', {}, el('a', { href, text: label })),
          ),
        ),
      );
    footer.replaceChildren(
      el(
        'div',
        { class: 'wrap' },
        el(
          'div',
          {},
          el('img', {
            src: BASE + 'assets/ui/launch/logo_bupbup.png',
            alt: 'BỤP BỤP!',
            loading: 'lazy',
          }),
          el('p', {
            text: 'Game đặt bom nước vui nhộn: đấu trí cùng bạn bè, chơi miễn phí trên Windows và trình duyệt.',
          }),
        ),
        list('Trò chơi', [
          [BASE + 'characters/', 'Nhân vật'],
          [BASE + 'maps/', 'Bản đồ'],
          [BASE + 'guide/', 'Hướng dẫn'],
          [BASE + 'download/', 'Tải game'],
        ]),
        list('Cộng đồng', [
          [BASE + 'events/', 'Sự kiện'],
          [BASE + 'rankings/', 'Bảng xếp hạng'],
          [BASE + 'news/', 'Tin tức'],
        ]),
        list('Hỗ trợ', [
          [BASE + 'support/', 'Trung tâm hỗ trợ'],
          [BASE + 'privacy/', 'Chính sách riêng tư'],
          [BASE + 'terms/', 'Điều khoản sử dụng'],
        ]),
        el('p', {
          class: 'legal',
          text: `© ${new Date().getFullYear()} BỤP BỤP! · Bản demo thử nghiệm. Hình ảnh, nhân vật và bản đồ thuộc dự án BỤP BỤP!.`,
        }),
      ),
    );
  }
  const tabbar = el('nav', {
    class: 'tabbar',
    'aria-label': 'Điều hướng nhanh',
  });
  for (const [path, label, icon] of TABS) {
    tabbar.append(
      el(
        'a',
        {
          href: BASE + path,
          'aria-current': current(path) ? 'page' : null,
          icon,
        },
        label,
      ),
    );
  }
  document.body.append(tabbar);
}

// ------------------------------------------------------------------ shared cards

function newsCard(item) {
  return el(
    'a',
    {
      class: 'card',
      href: `${BASE}news/post/?slug=${encodeURIComponent(item.slug)}`,
    },
    el(
      'div',
      { class: 'thumb' },
      img(item.image, ''),
      el('span', {
        class: `tag ${categoryClass(item.category)}`,
        text: item.category,
      }),
    ),
    el(
      'div',
      { class: 'body' },
      el('h3', { text: item.title }),
      el('time', { datetime: item.date, text: formatDate(item.date) }),
      el('p', { text: item.excerpt }),
    ),
  );
}

function characterCard(hero, full = false) {
  const stats = [
    ['Tốc độ', hero.stats.speed],
    ['Số bom', hero.stats.bombs],
    ['Tầm nổ', hero.stats.range],
  ];
  return el(
    'article',
    { class: 'card hero-card', id: hero.id },
    img(hero.portrait, hero.name, {
      class: 'portrait',
      width: 120,
      height: 120,
    }),
    el('h3', { text: hero.name }),
    el('span', { class: 'chip', text: hero.role }),
    full ? el('p', { text: hero.desc }) : null,
    full
      ? el(
          'div',
          { class: 'stats' },
          ...stats.map(([label, value]) => {
            const fill = el('i');
            fill.style.width = `${Math.min(100, (value / 5) * 100)}%`;
            return el(
              'div',
              { class: 'stat' },
              el('span', { text: label }),
              el(
                'span',
                {
                  class: 'bar',
                  role: 'img',
                  'aria-label': `${label} ${value}/5`,
                },
                fill,
              ),
            );
          }),
        )
      : el('a', {
          class: 'btn btn-line btn-sm',
          href: `${BASE}characters/#${hero.id}`,
          text: 'Xem chi tiết',
        }),
  );
}

function mapCard(map, full = false) {
  return el(
    'article',
    { class: 'card map-card' },
    el('div', { class: 'thumb' }, img(map.image, `Bản đồ ${map.name}`)),
    el(
      'div',
      { class: 'body' },
      el('h3', { text: map.name }),
      el('span', { class: 'meta', text: map.subtitle }),
      full && map.story ? el('p', { text: map.story }) : null,
      el(
        'div',
        { class: 'chips' },
        el('span', { class: 'chip', text: map.size }),
        el('span', { class: 'chip', text: `${map.players} người` }),
        map.admin ? el('span', { class: 'chip', text: 'Mới' }) : null,
      ),
    ),
  );
}

const EVENT_STATUS = {
  live: 'Đang diễn ra',
  upcoming: 'Sắp diễn ra',
  ended: 'Đã kết thúc',
};

function eventCard(event) {
  const when =
    event.status === 'upcoming'
      ? `Bắt đầu ${timeFmt.format(new Date(event.start_at))}`
      : `${formatDate(event.start_at)} – ${formatDate(event.end_at)}`;
  return el(
    'article',
    { class: 'card' },
    el(
      'div',
      { class: 'thumb' },
      img(BASE + 'img/news-event.webp', ''),
      el('span', {
        class: `tag ${event.status}`,
        text: EVENT_STATUS[event.status],
      }),
    ),
    el(
      'div',
      { class: 'body' },
      el('h3', { text: event.name }),
      el('span', { class: 'meta', text: when }),
      el('p', {
        text:
          event.description ||
          event.intro ||
          'Tham gia trong game để nhận quà.',
      }),
    ),
  );
}

// ------------------------------------------------------------------ gallery

const SHOTS = [
  ['gameplay-online.webp', 'Trận online với thanh vật phẩm CÁ NHÂN'],
  ['gameplay-practice.webp', 'Luyện tập cùng 3 bot trên Công Viên Kẹo'],
  ['gameplay-friends.webp', 'Phòng luyện tập: bạn bè và bot cùng đấu'],
  ['gameplay-moon.webp', 'Bản đồ Cung Điện Trăng khổ 17×13'],
  ['gameplay-pastry.webp', 'Bản đồ Tiệm Bánh Mây'],
];

function openGallery(start = 0) {
  let index = start;
  const picture = el('img', { alt: '' });
  const caption = el('figcaption');
  const show = () => {
    picture.src = BASE + 'img/' + SHOTS[index][0];
    picture.alt = SHOTS[index][1];
    caption.textContent = `${index + 1}/${SHOTS.length} · ${SHOTS[index][1]}`;
  };
  const step = (by) => {
    index = (index + by + SHOTS.length) % SHOTS.length;
    show();
  };
  const close = () => {
    box.remove();
    document.removeEventListener('keydown', keys);
    opener?.focus();
  };
  const keys = (e) => {
    if (e.key === 'Escape') close();
    if (e.key === 'ArrowRight') step(1);
    if (e.key === 'ArrowLeft') step(-1);
  };
  const opener = document.activeElement;
  const closeButton = el('button', {
    class: 'btn btn-sun btn-sm',
    type: 'button',
    onclick: close,
    text: 'Đóng',
  });
  const box = el(
    'div',
    {
      class: 'lightbox open',
      role: 'dialog',
      'aria-modal': 'true',
      'aria-label': 'Ảnh gameplay',
      onclick: (e) => e.target === box && close(),
    },
    el(
      'figure',
      {},
      picture,
      caption,
      el(
        'div',
        { class: 'controls' },
        el('button', {
          class: 'btn btn-line btn-sm',
          type: 'button',
          onclick: () => step(-1),
          text: '‹ Trước',
        }),
        el('button', {
          class: 'btn btn-line btn-sm',
          type: 'button',
          onclick: () => step(1),
          text: 'Sau ›',
        }),
        closeButton,
      ),
    ),
  );
  show();
  document.body.append(box);
  document.addEventListener('keydown', keys);
  closeButton.focus();
}

// ------------------------------------------------------------------ pages

// Hero text from the Admin Portal; the static HTML already shows the defaults.
function applyHero() {
  load(`${API}/v1/public/site`)
    .then(({ hero }) => {
      const title = document.getElementById('hero-title');
      if (!title || !hero) return;
      title.replaceChildren(
        hero.headline,
        hero.headline_accent ? el('span', { text: hero.headline_accent }) : '',
      );
      const sub = document.getElementById('hero-sub');
      sub.textContent = hero.subline;
      sub.style.display = hero.subline ? '' : 'none';
      for (const [key, label] of [
        ['download', hero.cta_download],
        ['play', hero.cta_demo],
      ]) {
        const button = document.querySelector(
          `.hero .hero-cta [data-cta="${key}"]`,
        );
        if (button && label) button.lastChild.textContent = label;
      }
    })
    .catch(() => {});
}

async function pageHome() {
  applyHero();
  document
    .querySelectorAll('[data-gallery]')
    .forEach((button) =>
      button.addEventListener('click', () =>
        openGallery(Number(button.dataset.gallery) || 0),
      ),
    );
  const news = document.getElementById('home-news');
  skeletons(news, 3);
  newsData()
    .then((list) => news.replaceChildren(...list.slice(0, 3).map(newsCard)))
    .catch(() => state(news, 'Chưa tải được tin tức.'));
  const heroes = document.getElementById('home-characters');
  const maps = document.getElementById('home-maps');
  skeletons(heroes, 5, 200);
  skeletons(maps, 4, 200);
  gameData()
    .then((data) => {
      heroes.replaceChildren(...data.characters.map((h) => characterCard(h)));
      maps.replaceChildren(...data.maps.slice(0, 4).map((m) => mapCard(m)));
    })
    .catch(() => {
      state(heroes, 'Chưa tải được nhân vật.');
      state(maps, 'Chưa tải được bản đồ.');
    });
  // Event teaser in the hero: the live event, else the generic weekly card.
  load(`${API}/v1/public/events`)
    .then(({ events }) => {
      const live =
        events.find((e) => e.status === 'live') ||
        events.find((e) => e.status === 'upcoming');
      if (!live) return;
      const badge = document.getElementById('event-badge');
      badge.querySelector('strong').textContent = live.name;
      badge.querySelector('small').textContent =
        live.status === 'live'
          ? `Đến ${formatDate(live.end_at)}`
          : `Từ ${formatDate(live.start_at)}`;
      badge.querySelector('.tag').textContent =
        live.status === 'live' ? 'Sự kiện mới' : 'Sắp diễn ra';
    })
    .catch(() => {});
}

async function pageCharacters() {
  const list = document.getElementById('character-list');
  skeletons(list, 5, 320);
  try {
    const data = await gameData();
    list.replaceChildren(...data.characters.map((h) => characterCard(h, true)));
    if (location.hash)
      document.getElementById(location.hash.slice(1))?.scrollIntoView();
  } catch {
    state(list, 'Chưa tải được nhân vật.', pageCharacters);
  }
}

async function pageMaps() {
  const list = document.getElementById('map-list');
  const tabs = document.getElementById('map-tabs');
  skeletons(list, 6, 260);
  let maps;
  try {
    const data = await gameData();
    maps = data.maps;
    // Maps an admin published on the server are playable too.
    const extra = await load(`${API}/v1/maps`).catch(() => ({ maps: [] }));
    for (const m of extra.maps || []) {
      if (maps.some((x) => x.id === m.id)) continue;
      maps.push({
        id: m.id,
        name: String(m.name || m.id),
        subtitle: String(m.subtitle || ''),
        story: String(m.story || ''),
        size: `${m.columns}×${m.rows}`,
        players: '2–4',
        image: BASE + 'img/news-maps.webp',
        admin: true,
        pack: '999',
      });
    }
  } catch {
    state(list, 'Chưa tải được bản đồ.', pageMaps);
    return;
  }
  const filters = [
    ['all', 'Tất cả', () => true],
    ['easy', 'Dễ', (m) => m.subtitle.startsWith('Dễ')],
    ['mid', 'Trung bình', (m) => m.subtitle.startsWith('Trung bình')],
    ['hard', 'Khó', (m) => m.subtitle.startsWith('Khó')],
    ['big', 'Khổ lớn 17×13', (m) => m.size === '17×13'],
  ];
  const show = (key) => {
    const [, , test] = filters.find((f) => f[0] === key);
    const shown = maps.filter(test);
    tabs
      .querySelectorAll('button')
      .forEach((b) =>
        b.setAttribute('aria-selected', String(b.dataset.key === key)),
      );
    if (shown.length)
      list.replaceChildren(...shown.map((m) => mapCard(m, true)));
    else state(list, 'Chưa có bản đồ trong nhóm này.');
  };
  tabs.replaceChildren(
    ...filters.map(([key, label]) =>
      el('button', {
        type: 'button',
        role: 'tab',
        'data-key': key,
        onclick: () => show(key),
        text: label,
      }),
    ),
  );
  show('all');
}

async function pageEvents() {
  const list = document.getElementById('event-list');
  const tabs = document.getElementById('event-tabs');
  const spot = document.getElementById('event-spotlight');
  skeletons(list, 3);
  let events;
  try {
    events = (await load(`${API}/v1/public/events`)).events;
  } catch {
    cache.delete(`${API}/v1/public/events`);
    state(list, 'Chưa tải được sự kiện. Vui lòng thử lại sau.', pageEvents);
    return;
  }
  const live = events.find((e) => e.status === 'live');
  if (live) {
    spot.hidden = false;
    spot.querySelector('h2').textContent = live.name;
    spot.querySelector('p').textContent =
      live.description || live.intro || 'Tham gia ngay trong game để nhận quà.';
    const left = () => {
      const ms = new Date(live.end_at) - Date.now();
      const d = Math.max(0, Math.floor(ms / 86400000));
      const h = Math.max(0, Math.floor((ms % 86400000) / 3600000));
      spot.querySelector('.countdown').textContent =
        ms > 0 ? `Còn ${d} ngày ${h} giờ` : 'Đã kết thúc';
    };
    left();
    setInterval(left, 60000);
  }
  const show = (status) => {
    tabs
      .querySelectorAll('button')
      .forEach((b) =>
        b.setAttribute('aria-selected', String(b.dataset.key === status)),
      );
    const shown = events.filter((e) => e.status === status);
    if (shown.length) list.replaceChildren(...shown.map(eventCard));
    else
      state(
        list,
        status === 'live'
          ? 'Hiện chưa có sự kiện nào đang diễn ra. Theo dõi Tin tức để không bỏ lỡ!'
          : 'Chưa có sự kiện trong mục này.',
      );
  };
  tabs.replaceChildren(
    ...Object.entries(EVENT_STATUS).map(([key, label]) =>
      el('button', {
        type: 'button',
        role: 'tab',
        'data-key': key,
        onclick: () => show(key),
        text: label,
      }),
    ),
  );
  show(live || !events.length ? 'live' : events[0].status);
}

async function pageRankings() {
  const podium = document.getElementById('podium');
  const body = document.getElementById('ranking-body');
  const tabs = document.getElementById('ranking-tabs');
  const updated = document.getElementById('ranking-updated');
  const show = async (period) => {
    tabs
      .querySelectorAll('button')
      .forEach((b) =>
        b.setAttribute('aria-selected', String(b.dataset.key === period)),
      );
    body.replaceChildren(
      el('tr', {}, el('td', { colspan: 6 }, el('div', { class: 'skeleton' }))),
    );
    podium.replaceChildren();
    let data;
    try {
      data = await getJSON(
        `${API}/v1/public/rankings?period=${period}&limit=50`,
      );
    } catch {
      body.replaceChildren(
        el(
          'tr',
          {},
          el('td', {
            colspan: 6,
            text: 'Chưa tải được bảng xếp hạng. Vui lòng thử lại sau.',
          }),
        ),
      );
      return;
    }
    updated.textContent = `Cập nhật lúc ${timeFmt.format(new Date(data.updated_at))} · tính các trận online đã được máy chủ xác nhận (3 điểm/thắng, 1 điểm/hạ gục).`;
    const face = (p) =>
      `${BASE}assets/characters/portraits/${HERO_NAMES[p.hero] ? p.hero : 'bombo'}.png`;
    if (!data.players.length) {
      body.replaceChildren(
        el(
          'tr',
          {},
          el('td', {
            colspan: 6,
            text: 'Chưa có trận online nào trong thời gian này. Hãy là người đầu tiên!',
          }),
        ),
      );
      return;
    }
    const order = [
      [data.players[1], 'second', 2],
      [data.players[0], 'first', 1],
      [data.players[2], 'third', 3],
    ];
    podium.replaceChildren(
      ...order.map(([p, cls, n]) =>
        p
          ? el(
              'div',
              { class: `step ${cls}` },
              img(face(p), ''),
              el('div', { class: 'name', text: p.name }),
              el('small', { text: `${p.points} điểm` }),
              el('div', { class: 'block', text: n }),
            )
          : el('div'),
      ),
    );
    body.replaceChildren(
      ...data.players.map((p) =>
        el(
          'tr',
          {},
          el('td', { text: p.rank }),
          el('td', {}, el('span', { class: 'who' }, img(face(p), ''), p.name)),
          el('td', { class: 'num', text: p.points }),
          el('td', { class: 'num', text: p.wins }),
          el('td', { class: 'num', text: p.kills }),
          el('td', { class: 'num', text: p.matches }),
        ),
      ),
    );
  };
  tabs.replaceChildren(
    ...[
      ['week', '7 ngày qua'],
      ['all', 'Mọi thời gian'],
    ].map(([key, label]) =>
      el('button', {
        type: 'button',
        role: 'tab',
        'data-key': key,
        onclick: () => show(key),
        text: label,
      }),
    ),
  );
  show('week');
}

async function pageNews() {
  const list = document.getElementById('news-list');
  skeletons(list, 3);
  try {
    list.replaceChildren(...(await newsData()).map(newsCard));
  } catch {
    state(list, 'Chưa tải được tin tức.', pageNews);
  }
}

async function pagePost() {
  const article = document.getElementById('post');
  const slug = new URLSearchParams(location.search).get('slug');
  try {
    const item = slug ? await postData(slug) : null;
    if (!item) {
      state(article, 'Không tìm thấy bài viết.');
      return;
    }
    document.title = `${item.title} · BỤP BỤP!`;
    article.replaceChildren(
      el('span', {
        class: `tag ${categoryClass(item.category)}`,
        text: item.category,
      }),
      el('h1', { text: item.title }),
      el('time', { datetime: item.date, text: formatDate(item.date) }),
      img(item.image, item.title),
      ...item.body.map((p) => el('p', { text: p })),
      el('p', {}, el('a', { href: BASE + 'news/', text: '← Tất cả tin tức' })),
    );
  } catch {
    state(article, 'Chưa tải được bài viết.', pagePost);
  }
}

async function pageDownload() {
  const card = document.getElementById('download-card');
  const release = await releaseData();
  const button = card.querySelector('[data-file]');
  const facts = card.querySelector('dl');
  if (!release || !release.downloadUrl) {
    button.setAttribute('aria-disabled', 'true');
    button.removeAttribute('href');
    button.lastChild.textContent = 'Đang cập nhật bản tải';
    facts.replaceChildren(
      el('dt', { text: 'Trạng thái' }),
      el('dd', {
        text: 'Bản Windows mới đang được chuẩn bị. Bạn có thể chơi thử bản Web ngay.',
      }),
    );
    return;
  }
  button.href = release.downloadUrl;
  button.setAttribute('download', '');
  const rows = [
    ['Phiên bản', release.version],
    ['Dung lượng', formatSize(release.fileSizeBytes)],
    ['Phát hành', formatDate(release.publishedAt)],
    ['Hệ điều hành', 'Windows 10/11 64-bit'],
    ['SHA-256', release.sha256],
  ];
  facts.replaceChildren(
    ...rows.flatMap(([k, v]) => [
      el('dt', { text: k }),
      el('dd', { class: k === 'SHA-256' ? 'sha' : null, text: v }),
    ]),
  );
  if (release.notes)
    document.getElementById('release-notes').textContent = release.notes;
}

async function pageGuide() {
  const list = document.getElementById('item-list');
  try {
    const data = await gameData();
    list.replaceChildren(
      ...data.items.map((item) =>
        el(
          'article',
          { class: 'card item-card' },
          img(item.icon, ''),
          el(
            'div',
            {},
            el('h3', { text: `${item.slot}. ${item.name}` }),
            el('p', { text: item.desc }),
          ),
        ),
      ),
    );
  } catch {
    state(list, 'Chưa tải được danh sách vật phẩm.', pageGuide);
  }
}

// Every page's "download" CTAs follow the published release (or the download page).
async function wireCtas() {
  document.querySelectorAll('[data-demo]').forEach((a) => (a.href = DEMO_URL));
}

const PAGES = {
  home: pageHome,
  characters: pageCharacters,
  maps: pageMaps,
  events: pageEvents,
  rankings: pageRankings,
  news: pageNews,
  post: pagePost,
  download: pageDownload,
  guide: pageGuide,
};

renderHeader();
renderFooter();
wireCtas();
PAGES[document.body.dataset.page]?.();
