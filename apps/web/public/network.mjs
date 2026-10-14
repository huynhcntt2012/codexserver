const actions = new Set(['up', 'down', 'left', 'right', 'bomb', 'ready']);
const messages = {
  401: 'Tên tài khoản hoặc mật khẩu chưa đúng. Hãy đăng nhập lại.',
  403: 'Phiên đăng nhập bị từ chối. Hãy đăng nhập lại.',
  409: 'Tên tài khoản đã được dùng. Hãy chọn tên khác hoặc đăng nhập.',
  422: 'Tên tài khoản cần 3–24 ký tự a-z, 0-9, _. Mật khẩu cần 10–128 ký tự.',
  429: 'Bạn thao tác quá nhanh. Vui lòng chờ một phút rồi thử lại.',
  503: 'Máy chủ tạm thời chưa sẵn sàng. Vui lòng thử lại.',
};

export function encodeAction(action) {
  if (!actions.has(action)) return null;
  return new Uint8Array([
    13,
    0,
    0xa0 + action.length,
    ...new TextEncoder().encode(action),
  ]);
}

export function validateCredentials(mode, username, password, confirmation) {
  if (mode === 'guest') return '';
  if (!/^[a-z0-9_]{3,24}$/.test(username.trim())) return messages[422];
  if ([...password].length < 10 || [...password].length > 128)
    return messages[422];
  if (mode === 'register' && password !== confirmation)
    return 'Mật khẩu nhập lại chưa khớp.';
  return '';
}

// Tokens live in this object only. Reloading the page ends the local session.
export class ArenaClient extends EventTarget {
  constructor(base = globalThis.location?.origin) {
    super();
    this.base = base;
    this.session = null;
    this.socket = null;
    this.snapshot = null;
    this.connected = false;
    this.busy = false;
    this.generation = 0;
  }

  emit(type, detail) {
    this.dispatchEvent(new CustomEvent(type, { detail }));
  }

  hasSession() {
    return !!this.session && this.session.deadline > Date.now();
  }

  async request(path, body, token, signal) {
    let response;
    try {
      response = await fetch(new URL(path, this.base), {
        method: body === undefined ? 'GET' : 'POST',
        headers: {
          'Content-Type': 'application/json',
          ...(token ? { Authorization: `Bearer ${token}` } : {}),
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        signal: signal
          ? AbortSignal.any([signal, AbortSignal.timeout(12000)])
          : AbortSignal.timeout(12000),
        cache: 'no-store',
      });
    } catch {
      throw new Error('Không kết nối được máy chủ. Kiểm tra mạng rồi thử lại.');
    }
    if (!response.ok) {
      if (
        response.status === 401 &&
        path.startsWith('/arena/') &&
        this.session?.token === token
      ) {
        this.session = null;
        this.emit('account', null);
      }
      throw new Error(
        (path.startsWith('/arena/matchmake/') &&
        response.status !== 429 &&
        response.status !== 503
          ? 'Phòng đã đầy, đã bắt đầu hoặc không còn tồn tại. Hãy chọn phòng khác.'
          : messages[response.status]) ||
          `Máy chủ trả lỗi ${response.status}. Vui lòng thử lại.`,
      );
    }
    try {
      const data = await response.json();
      if (!data || typeof data !== 'object' || Array.isArray(data))
        throw new Error();
      return data;
    } catch {
      throw new Error('Phản hồi máy chủ không hợp lệ.');
    }
  }

  requireSession() {
    if (this.hasSession()) return this.session.token;
    this.session = null;
    this.emit('account', null);
    throw new Error('Phiên đã hết hạn. Vui lòng đăng nhập lại.');
  }

  async authenticate({
    mode = 'login',
    username = '',
    password = '',
    confirmation = '',
  } = {}) {
    if (this.busy || this.connected) return;
    const error = validateCredentials(mode, username, password, confirmation);
    if (error) throw new Error(error);
    const path = { guest: 'guests', login: 'login', register: 'register' }[
      mode
    ];
    if (!path) throw new Error('Chế độ đăng nhập không hợp lệ.');
    this.busy = true;
    const generation = ++this.generation;
    this.controller = new AbortController();
    this.session = null;
    this.emit('status', 'Đang xác thực tài khoản…');
    try {
      const auth = await this.request(
        `/api/v1/${path}`,
        mode === 'guest' ? {} : { username: username.trim(), password },
        null,
        this.controller.signal,
      );
      if (generation !== this.generation) return;
      if (typeof auth.access_token !== 'string' || !auth.access_token)
        throw new Error('Máy chủ chưa cấp phiên đăng nhập.');
      this.session = {
        token: auth.access_token,
        name: auth.name,
        deadline:
          Date.now() + Math.max(0, Number(auth.expires_in || 0) - 10) * 1000,
      };
      this.emit('account', this.session.name);
      this.emit(
        'status',
        'Đăng nhập thành công. Chọn một phòng chờ hoặc tạo phòng mới.',
      );
    } finally {
      if (generation === this.generation) {
        this.busy = false;
        this.emit('change');
      }
    }
  }

  async listRooms() {
    const token = this.requireSession();
    const data = await this.request('/arena/rooms', undefined, token);
    if (!Array.isArray(data.rooms))
      throw new Error('Danh sách phòng không hợp lệ.');
    return data.rooms;
  }

  // Compatibility helper for headless clients; the website uses separate steps.
  async join(options = { mode: 'guest' }) {
    if (this.busy || this.connected) return;
    if (options.mode !== 'session') await this.authenticate(options);
    await this.joinRoom();
  }

  async joinRoom({ roomId, create = false } = {}) {
    if (this.busy || this.connected) return;
    const token = this.requireSession();
    this.busy = true;
    const generation = ++this.generation;
    this.controller = new AbortController();
    this.emit('status', create ? 'Đang tạo phòng…' : 'Đang vào phòng…');
    try {
      const route = create
        ? 'create/arena'
        : roomId
          ? `joinById/${encodeURIComponent(roomId)}`
          : 'joinOrCreate/arena';
      const seat = await this.request(
        `/arena/matchmake/${route}`,
        { token },
        null,
        this.controller.signal,
      );
      if (generation !== this.generation) return;
      if (
        !['roomId', 'processId', 'sessionId'].every(
          (key) => typeof seat[key] === 'string' && seat[key],
        )
      )
        throw new Error(
          'Phòng đã đầy, đã bắt đầu hoặc không còn tồn tại. Hãy chọn phòng khác.',
        );
      this.id = seat.sessionId;
      this.roomId = seat.roomId;
      const url = new URL(
        `/arena/${encodeURIComponent(seat.processId)}/${encodeURIComponent(seat.roomId)}`,
        this.base,
      );
      url.protocol = url.protocol === 'https:' ? 'wss:' : 'ws:';
      url.searchParams.set('sessionId', seat.sessionId);
      await this.openSocket(url, generation);
    } finally {
      if (generation === this.generation) {
        this.busy = false;
        this.emit('change');
      }
    }
  }

  openSocket(url, generation) {
    return new Promise((resolve, reject) => {
      const socket = (this.socket = new WebSocket(url));
      socket.binaryType = 'arraybuffer';
      let joined = false;
      const fail = (message) => {
        clearTimeout(timer);
        socket.close();
        reject(new Error(message));
      };
      const timer = setTimeout(
        () => fail('Kết nối phòng quá thời gian. Hãy thử lại.'),
        12000,
      );
      socket.addEventListener('message', (event) => {
        if (generation !== this.generation) return;
        const bytes = new Uint8Array(event.data);
        if (bytes[0] === 10) {
          socket.send(new Uint8Array([10]));
          joined = this.connected = true;
          clearTimeout(timer);
          this.emit('status', 'Đã vào phòng. Sẵn sàng khi bạn muốn bắt đầu!');
          this.emit('change');
          resolve();
        } else if (bytes[0] === 17 && bytes[1] === 1) {
          try {
            const snapshot = JSON.parse(
              new TextDecoder().decode(bytes.slice(2)),
            );
            if (
              snapshot.version === 1 &&
              Array.isArray(snapshot.players) &&
              Array.isArray(snapshot.grid)
            ) {
              this.snapshot = snapshot;
              this.emit('snapshot', snapshot);
            }
          } catch {
            fail('Dữ liệu trận đấu không hợp lệ. Hãy vào lại phòng.');
          }
        } else if (bytes[0] === 11 || bytes[0] === 12) {
          fail('Phòng đã đóng hoặc từ chối phiên. Hãy thử đăng nhập lại.');
        }
      });
      socket.addEventListener('error', () =>
        fail('Không kết nối được phòng chơi. Vui lòng thử lại.'),
      );
      socket.addEventListener('close', () => {
        clearTimeout(timer);
        if (!joined) reject(new Error('Phòng đã đóng hoặc từ chối kết nối.'));
        if (generation !== this.generation) return;
        this.connected = false;
        this.snapshot = null;
        this.emit('status', 'Đã mất kết nối. Vào lại để tìm phòng mới.');
        this.emit('change');
      });
    });
  }

  send(action) {
    const packet = encodeAction(action);
    if (packet && this.connected && this.socket?.readyState === WebSocket.OPEN)
      this.socket.send(packet);
  }

  leave() {
    ++this.generation;
    this.controller?.abort();
    if (this.socket?.readyState === WebSocket.OPEN)
      this.socket.send(new Uint8Array([12]));
    this.socket?.close();
    this.socket = null;
    this.connected = this.busy = false;
    this.snapshot = null;
    this.emit('status', 'Đã rời phòng. Bạn có thể vào chơi lại.');
    this.emit('change');
  }

  logout() {
    this.leave();
    this.session = null;
    this.emit('account', null);
  }
}
