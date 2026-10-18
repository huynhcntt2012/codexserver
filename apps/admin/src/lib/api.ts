// Admin API client. Calls go through the web nginx at /admin/api -> FastAPI /admin/v1.
// The admin token lives in sessionStorage only, so closing the tab signs out.
const BASE = '/admin/api';
const TOKEN_KEY = 'bup-admin-token';

export class ApiError extends Error {
  constructor(
    public status: number,
    message: string,
  ) {
    super(message);
  }
}

const MESSAGES: Record<number, string> = {
  400: 'Yêu cầu chưa hợp lệ.',
  401: 'Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.',
  403: 'Vai trò của bạn không được phép làm việc này.',
  404: 'Không tìm thấy dữ liệu.',
  409: 'Dữ liệu đang xung đột hoặc đã tồn tại.',
  422: 'Thông tin nhập chưa hợp lệ.',
  429: 'Thử quá nhiều lần, vui lòng chờ vài phút.',
  503: 'Dịch vụ tạm thời không sẵn sàng.',
};

// Server details are short English strings; show the Vietnamese ones we know.
const DETAILS: Record<string, string> = {
  'Invalid credentials': 'Tên đăng nhập hoặc mật khẩu không đúng.',
  'MFA code required': 'Tài khoản bật MFA: nhập mã 6 số từ ứng dụng xác thực.',
  'Invalid MFA code': 'Mã MFA không đúng.',
  'Account already suspended': 'Tài khoản đang bị khóa.',
  'Player already owns this item': 'Người chơi đã có vật phẩm này.',
  'Item id already exists': 'ID vật phẩm đã tồn tại.',
  'Map id already exists': 'ID bản đồ đã tồn tại.',
  'Map id cannot change': 'Không đổi được ID của bản đồ đã tạo.',
  'Giftcode already exists': 'Mã quà tặng đã tồn tại.',
  'Pause the event before editing it': 'Hãy tạm dừng sự kiện trước khi sửa.',
  'Publish the item before selling it':
    'Cần phát hành vật phẩm trước khi mở bán.',
  'You cannot demote or disable yourself':
    'Không thể tự hạ quyền hoặc khóa chính mình.',
  'Keep at least one active owner': 'Cần giữ ít nhất một owner đang hoạt động.',
  'Admin username taken': 'Tên admin đã được dùng.',
  'Current password is wrong': 'Mật khẩu hiện tại không đúng.',
  'Slug already exists': 'Đường dẫn (slug) này đã có bài khác dùng.',
  'Post not found': 'Không tìm thấy bài viết (có thể đã bị xóa).',
};

export function getToken(): string | null {
  try {
    return sessionStorage.getItem(TOKEN_KEY);
  } catch {
    return null;
  }
}

export function setToken(token: string | null) {
  try {
    if (token) sessionStorage.setItem(TOKEN_KEY, token);
    else sessionStorage.removeItem(TOKEN_KEY);
  } catch {
    /* storage blocked: the session just will not survive a reload */
  }
}

function describe(status: number, body: unknown): string {
  const detail =
    body && typeof body === 'object' && 'detail' in body
      ? (body as { detail: unknown }).detail
      : null;
  if (typeof detail === 'string') {
    if (DETAILS[detail]) return DETAILS[detail];
    if (detail.startsWith('Unknown items'))
      return 'Có vật phẩm không nằm trong danh mục.';
    if (detail.startsWith('Cannot '))
      return 'Trạng thái hiện tại không cho phép thao tác này.';
  }
  // Map validation: {"errors": [...]} with Vietnamese reasons from the API.
  if (detail && typeof detail === 'object' && 'errors' in detail) {
    const errors = (detail as { errors: unknown }).errors;
    if (Array.isArray(errors) && errors.length) return errors.join(' · ');
  }
  if (Array.isArray(detail) && detail.length) {
    const first = detail[0] as { loc?: unknown[]; msg?: string };
    const field = first.loc?.slice(-1)[0];
    return `Trường "${String(field)}" chưa hợp lệ: ${first.msg ?? ''}`;
  }
  return MESSAGES[status] ?? `Máy chủ lỗi (HTTP ${status}).`;
}

export async function api<T>(
  path: string,
  options: { method?: string; body?: unknown } = {},
): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' };
  const token = getToken();
  if (token) headers.Authorization = `Bearer ${token}`;
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';
  let response: Response;
  try {
    response = await fetch(BASE + path, {
      method: options.method ?? 'GET',
      headers,
      body:
        options.body === undefined ? undefined : JSON.stringify(options.body),
      cache: 'no-store',
    });
  } catch {
    throw new ApiError(0, 'Không kết nối được máy chủ quản trị.');
  }
  const text = await response.text();
  let body: unknown = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = null;
  }
  if (!response.ok) {
    if (response.status === 401 && path !== '/auth/login') {
      setToken(null);
      if (!location.pathname.startsWith('/admin/login'))
        location.assign('/admin/login/');
    }
    throw new ApiError(response.status, describe(response.status, body));
  }
  return body as T;
}

/** Uploads a raw file body (item icons). */
export async function upload<T>(path: string, file: Blob): Promise<T> {
  const token = getToken();
  const response = await fetch(BASE + path, {
    method: 'POST',
    headers: {
      'Content-Type': file.type || 'application/octet-stream',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
    },
    body: file,
  });
  const text = await response.text();
  let body: unknown = null;
  try {
    body = text ? JSON.parse(text) : null;
  } catch {
    body = null;
  }
  if (!response.ok) {
    if (response.status === 413) throw new ApiError(413, 'Ảnh lớn hơn 10 MB.');
    if (response.status === 422)
      throw new ApiError(422, 'Ảnh phải là PNG 16–2048 px.');
    throw new ApiError(response.status, describe(response.status, body));
  }
  return body as T;
}
