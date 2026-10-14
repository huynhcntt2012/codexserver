import { ArenaClient } from './network.mjs';
import { drawBoard } from './renderer.mjs';

const $ = (id) => document.getElementById(id);
const client = new ArenaClient();
let mode = location.hash === '#register' ? 'register' : 'login';
let screen = '';
let loadingRooms = false;
let rooms = [];
let rosterKey = '';
let previousPhase;
// Keep touch controls adjacent to the board, including on narrow screens.
$('board').closest('.arena-panel').append($('touch-controls'));
const held = new Map();
const keys = {
  KeyW: 'up',
  ArrowUp: 'up',
  KeyS: 'down',
  ArrowDown: 'down',
  KeyA: 'left',
  ArrowLeft: 'left',
  KeyD: 'right',
  ArrowRight: 'right',
  Space: 'bomb',
  KeyR: 'ready',
};

function status(message, error = false) {
  $('status').textContent = message;
  $('status').classList.toggle('error', error);
}

function authView() {
  const register = mode === 'register';
  $('auth-title').textContent = register ? 'Tạo tài khoản' : 'Đăng nhập';
  $('auth-description').textContent = register
    ? 'Tạo tài khoản để cùng bạn bè vào đấu trường.'
    : 'Đăng nhập để xem danh sách phòng chờ.';
  $('confirmation').hidden = !register;
  $('confirm').required = register;
  $('confirm').disabled = !register || client.busy;
  $('password').autocomplete = register ? 'new-password' : 'current-password';
  $('username').disabled = $('password').disabled = client.busy;
  $('join').disabled = client.busy;
  $('join').textContent = client.busy
    ? 'Đang xác thực…'
    : register
      ? 'Tạo tài khoản →'
      : 'Đăng nhập →';
  $('auth-switch-copy').textContent = register
    ? 'Đã có tài khoản?'
    : 'Chưa có tài khoản?';
  $('auth-switch').textContent = register ? 'Đăng nhập' : 'Đăng ký';
  $('auth-switch').href = register ? '#login' : '#register';
  $('session-name').textContent = client.session
    ? `Xin chào, ${client.session.name}`
    : '';
}

window.addEventListener('hashchange', () => {
  if (!client.hasSession() && !client.busy) {
    mode = location.hash === '#register' ? 'register' : 'login';
    $('password').value = $('confirm').value = '';
    status('Đăng nhập hoặc tạo tài khoản để bắt đầu.');
  }
  authView();
  render();
});

function renderRooms() {
  $('create-room').disabled = client.busy;
  $('refresh-rooms').disabled = loadingRooms || client.busy;
  // Keep cards stable during polling so keyboard focus is not lost.
  const key = JSON.stringify([rooms, client.busy]);
  if ($('rooms-list').dataset.key === key) return;
  $('rooms-list').dataset.key = key;
  $('rooms-list').replaceChildren(
    ...rooms.map((room) => {
      const card = document.createElement('article');
      card.className = 'room-card';
      card.dataset.roomId = room.roomId;
      const tag = document.createElement('p');
      tag.className = 'eyebrow';
      tag.textContent = 'NEON GARDEN';
      const title = document.createElement('h2');
      title.textContent = `Phòng ${room.roomId}`;
      const count = document.createElement('p');
      count.className = 'muted';
      count.textContent = `${room.players}/${room.maxPlayers} người · ${room.ready} đã sẵn sàng`;
      const button = document.createElement('button');
      button.className = 'primary';
      button.textContent = room.joinable ? 'Vào phòng →' : 'Phòng đã đầy';
      button.disabled = !room.joinable || client.busy;
      button.addEventListener('click', () =>
        enterRoom({ roomId: room.roomId }),
      );
      card.append(tag, title, count, button);
      return card;
    }),
  );
}

async function refreshRooms() {
  if (loadingRooms || client.busy || client.connected || !client.session)
    return;
  loadingRooms = true;
  const session = client.session;
  renderRooms();
  try {
    const next = await client.listRooms();
    if (session !== client.session || client.connected) return;
    rooms = next;
    $('rooms-summary').textContent = `${rooms.length} phòng đang chờ`;
    $('rooms-empty').hidden = rooms.length > 0;
  } catch (error) {
    if (!client.session) status(error.message, true);
    if (session === client.session && !client.connected) {
      rooms = [];
      $('rooms-empty').hidden = true;
      $('rooms-summary').textContent =
        'Chưa tải được danh sách. Bấm Làm mới để thử lại.';
      status(error.message, true);
    }
  } finally {
    loadingRooms = false;
    renderRooms();
  }
}

async function enterRoom(options) {
  try {
    const pending = client.joinRoom(options);
    renderRooms();
    await pending;
    document.activeElement?.blur();
  } catch (error) {
    status(error.message, true);
    void refreshRooms();
  } finally {
    render();
    renderRooms();
  }
}
$('create-room').addEventListener('click', () => enterRoom({ create: true }));
$('refresh-rooms').addEventListener('click', refreshRooms);
setInterval(() => {
  if (!document.hidden && screen === 'rooms') void refreshRooms();
}, 5000);

$('auth-form').addEventListener('submit', async (event) => {
  event.preventDefault();
  const options = {
    mode,
    username: $('username').value,
    password: $('password').value,
    confirmation: $('confirm').value,
  };
  $('password').value = $('confirm').value = '';
  try {
    const pending = client.authenticate(options);
    authView();
    await pending;
    document.activeElement?.blur();
  } catch (error) {
    status(error.message, true);
  } finally {
    authView();
    render();
  }
});
$('logout').addEventListener('click', () => {
  mode = 'login';
  client.logout();
  authView();
  status('Đã đăng xuất. Nhập tài khoản để đăng nhập lại.');
});
$('leave').addEventListener('click', () => client.leave());
$('ready').addEventListener('click', () => {
  client.send('ready');
  $('ready').blur();
});
client.addEventListener('status', (event) => status(event.detail));
client.addEventListener('account', () => {
  authView();
  render();
});
client.addEventListener('change', () => {
  held.clear();
  authView();
  render();
});
client.addEventListener('snapshot', render);

function render() {
  const s = client.snapshot;
  const phase = s?.phase;
  const inGame = phase === 'playing' || phase === 'finished';
  const nextScreen = client.connected
    ? inGame
      ? 'game'
      : 'lobby'
    : client.hasSession()
      ? 'rooms'
      : 'auth';
  $('auth-panel').hidden = nextScreen !== 'auth';
  $('rooms-panel').hidden = nextScreen !== 'rooms';
  $('play-panel').hidden = !client.connected;
  $('board').closest('.arena-panel').hidden = !inGame;
  $('play-layout').classList.toggle('lobby-layout', !inGame);
  $('play-title').textContent = inGame ? 'Đấu trường' : 'Phòng chờ';
  for (const step of document.querySelectorAll('[data-step]'))
    step.classList.toggle('active', step.dataset.step === nextScreen);
  const route = nextScreen === 'auth' ? mode : nextScreen;
  if (location.hash !== `#${route}`)
    history.replaceState(null, '', `#${route}`);
  document.title = `${nextScreen === 'auth' ? (mode === 'register' ? 'Đăng ký' : 'Đăng nhập') : nextScreen === 'rooms' ? 'Chọn phòng' : inGame ? 'Đấu trường' : 'Phòng chờ'} · Suni Bomb Arena`;
  if (nextScreen !== screen) {
    screen = nextScreen;
    if (screen === 'rooms') {
      rooms = [];
      $('rooms-summary').textContent = 'Đang tải phòng chờ…';
      $('rooms-empty').hidden = true;
      renderRooms();
      // Authentication finishes before room discovery starts.
      queueMicrotask(refreshRooms);
    }
    $(
      screen === 'auth'
        ? 'auth-title'
        : screen === 'rooms'
          ? 'rooms-title'
          : 'play-title',
    ).focus({ preventScroll: true });
  }
  if (
    phase === 'playing' &&
    previousPhase !== phase &&
    matchMedia('(max-width: 680px)').matches
  ) {
    $('board').closest('.arena-panel').scrollIntoView({ block: 'start' });
  }
  previousPhase = phase;
  const players = s?.players || [];
  const self = players.find((p) => p.id === client.id);
  const seconds = s ? Math.max(0, Math.ceil((s.deadline - s.now) / 1000)) : 0;
  $('room-panel').hidden = !client.connected;
  $('connection').textContent = client.connected
    ? 'Đã kết nối'
    : client.busy
      ? 'Đang kết nối…'
      : 'Chưa vào phòng';
  $('connection-dot').classList.toggle('online', client.connected);
  $('round').textContent = s
    ? `VÁN ${s.round} / ${phase === 'waiting' ? `${players.length}/8 PHI CÔNG` : `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`}`
    : '2–8 NGƯỜI CHƠI';
  $('room-id').textContent = `PHÒNG / ${client.roomId || ''}`;
  $('room-title').textContent =
    phase === 'playing'
      ? self?.alive
        ? 'Trận đấu bắt đầu!'
        : 'Bạn đang theo dõi'
      : phase === 'finished'
        ? 'Kết quả ván đấu'
        : 'Sảnh chờ';
  $('room-hint').textContent =
    phase === 'waiting'
      ? `${players.filter((p) => p.ready).length}/${players.length} đã sẵn sàng · Tối thiểu 2 người`
      : phase === 'playing'
        ? `${players.filter((p) => p.alive).length} phi công còn sống`
        : phase === 'finished'
          ? `Ván mới sau ${seconds} giây`
          : `Bắt đầu sau ${seconds} giây`;
  $('ready').disabled = phase !== 'waiting' || !!self?.ready;
  $('ready').textContent =
    phase === 'waiting'
      ? self?.ready
        ? 'Đã sẵn sàng · Chờ bạn bè'
        : 'Sẵn sàng [R]'
      : phase === 'countdown'
        ? `Tất cả đã sẵn sàng · ${seconds} giây`
        : 'Ván đấu đang diễn ra';
  const nextKey = JSON.stringify([players, phase]);
  if (nextKey !== rosterKey) {
    rosterKey = nextKey;
    $('roster').replaceChildren(
      ...Array.from({ length: 8 }, (_, i) => {
        const player = players.find((p) => p.slot === i);
        const li = document.createElement('li');
        for (const [className, text] of [
          ['slot', String(i + 1).padStart(2, '0')],
          [
            'name',
            player
              ? player.name + (player.id === client.id ? ' (bạn)' : '')
              : 'Chờ phi công…',
          ],
          [
            'state',
            player
              ? ['waiting', 'countdown'].includes(phase)
                ? player.ready
                  ? 'SẴN SÀNG'
                  : 'ĐANG CHỜ'
                : player.alive
                  ? 'CÒN SỐNG'
                  : 'ĐÃ BỊ LOẠI'
              : '',
          ],
        ]) {
          const span = document.createElement('span');
          span.className = className;
          span.textContent = text;
          li.append(span);
        }
        return li;
      }),
    );
  }
  $('overlay').hidden =
    client.connected && !['countdown', 'finished'].includes(phase);
  let title = 'Chuẩn bị vào trận.',
    detail = 'Trận đấu bắt đầu khi tất cả người chơi sẵn sàng.',
    tag = 'SÂN ĐẤU ĐÃ SẴN SÀNG';
  if (phase === 'countdown') {
    title = String(seconds);
    detail = 'Chuẩn bị di chuyển. Nhớ tìm đường thoát!';
    tag = 'TẤT CẢ ĐÃ SẴN SÀNG';
  }
  if (phase === 'finished') {
    title =
      s.winner === null
        ? 'Một trận hòa!'
        : s.winner === client.id
          ? 'Bạn thắng rồi!'
          : `${players.find((p) => p.id === s.winner)?.name || 'Phi công'} chiến thắng!`;
    detail = `Tự trở về sảnh sau ${seconds} giây.`;
    tag = 'HẸN GẶP Ở VÁN TIẾP THEO';
  }
  $('overlay-title').textContent = title;
  $('overlay-detail').textContent = detail;
  $('overlay-tag').textContent = tag;
  $('touch-controls').hidden = phase !== 'playing' || !self?.alive;
}

function act(action) {
  if (action === 'ready' && !$('ready').disabled) client.send(action);
  else if (client.snapshot?.phase === 'playing') client.send(action);
}

document.addEventListener('keydown', (event) => {
  if (
    event.target.closest('input, textarea, button, a') ||
    !client.connected ||
    event.ctrlKey ||
    event.altKey ||
    event.metaKey
  )
    return;
  const action = keys[event.code];
  if (!action) return;
  event.preventDefault();
  if (!event.repeat) {
    act(action);
    if (!['bomb', 'ready'].includes(action)) held.set(event.code, action);
  }
});
document.addEventListener('keyup', (event) => held.delete(event.code));
window.addEventListener('blur', () => held.clear());
document.addEventListener('visibilitychange', () => held.clear());
for (const button of document.querySelectorAll('[data-action]')) {
  button.addEventListener('pointerdown', (event) => {
    event.preventDefault();
    button.setPointerCapture(event.pointerId);
    act(button.dataset.action);
    if (button.dataset.action !== 'bomb')
      held.set(event.pointerId, button.dataset.action);
  });
  for (const type of ['pointerup', 'pointercancel', 'lostpointercapture'])
    button.addEventListener(type, (event) => held.delete(event.pointerId));
}
window.addEventListener('pagehide', () => client.leave());
setInterval(() => {
  if (held.size) act([...held.values()].at(-1));
}, 160);
let lastDraw = 0;
function frame(time) {
  if (screen === 'game' && time - lastDraw > 32) {
    drawBoard($('board'), client.snapshot, client.id, time);
    lastDraw = time;
  }
  requestAnimationFrame(frame);
}
authView();
render();
requestAnimationFrame(frame);
