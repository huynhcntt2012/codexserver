// Display helpers: Vietnamese labels and Asia/Ho_Chi_Minh dates.
const TZ = 'Asia/Ho_Chi_Minh';

export function dateTime(value: string | null | undefined): string {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return date.toLocaleString('vi-VN', {
    timeZone: TZ,
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  });
}

export function shortDay(value: string): string {
  const [, month, day] = value.split('-');
  return `${day}/${month}`;
}

export function ago(value: string | null | undefined): string {
  if (!value) return '—';
  const seconds = Math.max(0, (Date.now() - new Date(value).getTime()) / 1000);
  if (seconds < 60) return 'vừa xong';
  if (seconds < 3600) return `${Math.floor(seconds / 60)} phút trước`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)} giờ trước`;
  return `${Math.floor(seconds / 86400)} ngày trước`;
}

export function number(value: number | null | undefined): string {
  return (value ?? 0).toLocaleString('vi-VN');
}

/** datetime-local input value (local time) <-> ISO string. */
export function toLocalInput(value: string | Date): string {
  const date = new Date(value);
  const offset = date.getTimezoneOffset() * 60000;
  return new Date(date.getTime() - offset).toISOString().slice(0, 16);
}

export function fromLocalInput(value: string): string {
  return new Date(value).toISOString();
}

export const CATEGORY: Record<string, string> = {
  consumable: 'Vật phẩm dùng',
  outfit: 'Trang phục',
  hat: 'Mũ',
  wings: 'Cánh',
  bomb_skin: 'Skin bom',
  effect: 'Hiệu ứng',
  pet: 'Pet',
  accessory: 'Phụ kiện',
};

export const RARITY: Record<string, [string, string]> = {
  common: ['Thường', ''],
  rare: ['Hiếm', 'blue'],
  epic: ['Sử thi', 'violet'],
  legendary: ['Huyền thoại', 'amber'],
};

export const PHASE: Record<string, [string, string]> = {
  draft: ['Bản nháp', ''],
  published: ['Đã phát hành', 'green'],
  hidden: ['Đang ẩn', ''],
  scheduled: ['Đã lên lịch', 'blue'],
  running: ['Đang chạy', 'green'],
  paused: ['Tạm dừng', 'amber'],
  ended: ['Đã kết thúc', ''],
  active: ['Đang hoạt động', 'green'],
  disabled: ['Đã tắt', 'red'],
  expired: ['Hết hạn', ''],
  exhausted: ['Hết lượt', 'amber'],
  on_sale: ['Đang bán', 'green'],
};

export const EVENT_KIND: Record<string, string> = {
  login: 'Đăng nhập nhận quà',
  match: 'Hoàn thành trận',
  rank: 'Đua rank',
  collect: 'Thu thập',
  shop: 'Ưu đãi shop',
  custom: 'Tùy chỉnh',
  story: 'Cốt truyện nhiều chương',
  challenge: 'Thử thách có thời hạn',
  boss: 'Đại Chiến Boss',
};

export const ROLE: Record<string, string> = {
  owner: 'Owner (toàn quyền)',
  operator: 'Operator (vận hành)',
  viewer: 'Viewer (chỉ xem)',
};

export const ACTION: Record<string, string> = {
  'admin.login': 'Đăng nhập quản trị',
  'admin.login_failed': 'Đăng nhập thất bại',
  'admin.created': 'Tạo admin',
  'admin.created_cli': 'Tạo admin (CLI)',
  'admin.updated': 'Cập nhật admin',
  'admin.password_changed': 'Đổi mật khẩu admin',
  'admin.password_reset_cli': 'Đặt lại mật khẩu (CLI)',
  'admin.mfa_enabled': 'Bật MFA',
  'account.ban': 'Khóa tài khoản',
  'account.unban': 'Mở khóa tài khoản',
  'inventory.grant': 'Tặng vật phẩm',
  'inventory.revoke': 'Thu hồi vật phẩm',
  'chat.delete': 'Xóa tin nhắn',
  'item.create': 'Tạo vật phẩm',
  'item.update': 'Sửa vật phẩm',
  'item.publish': 'Phát hành vật phẩm',
  'item.hide': 'Ẩn vật phẩm',
  'event.create': 'Tạo sự kiện',
  'event.update': 'Sửa sự kiện',
  'event.publish': 'Phát hành sự kiện',
  'event.pause': 'Tạm dừng sự kiện',
  'event.resume': 'Tiếp tục sự kiện',
  'giftcode.create': 'Tạo giftcode',
  'giftcode.disable': 'Tắt giftcode',
  'giftcode.enable': 'Bật giftcode',
  'offer.create': 'Tạo ưu đãi shop',
  'offer.publish': 'Mở bán',
  'offer.pause': 'Dừng bán',
  'account.edit': 'Sửa thông tin tài khoản',
  'wallet.adjust': 'Điều chỉnh ví',
  'item.icon': 'Cập nhật ảnh vật phẩm',
  'map.create': 'Tạo bản đồ',
  'map.update': 'Sửa bản đồ',
  'map.publish': 'Phát hành bản đồ',
  'map.hide': 'Ẩn bản đồ',
  'quest.save': 'Lưu nhiệm vụ',
  'quest.seed': 'Thêm nhiệm vụ mặc định',
};

/** Item art copied from the game into /admin/game at build time. */
export function iconUrl(
  icon: string | null | undefined,
  sha?: string | null,
): string | null {
  // Server copy (what clients download) wins over the bundled admin copy.
  if (sha) return `/api/v1/assets/${sha}.png`;
  return icon ? `/admin/game/${icon}` : null;
}

/** Wallet ledger kinds: [label, badge tone]. */
export const KIND: Record<string, [string, string]> = {
  welcome: ['Quà tân thủ', 'violet'],
  topup: ['Nạp (sandbox)', 'green'],
  exchange: ['Đổi KC ↔ vàng', 'blue'],
  purchase: ['Mua vật phẩm', 'amber'],
  admin_adjust: ['Admin điều chỉnh', 'red'],
};
