import { test, expect } from '@playwright/test';

// Read-only walk through the admin portal against a real stack. Needs an admin
// account: SUNI_ADMIN_USER / SUNI_ADMIN_PASSWORD. Set SUNI_CAPTURE_DIR for screenshots.
const user = process.env.SUNI_ADMIN_USER;
const password = process.env.SUNI_ADMIN_PASSWORD;
const capture = process.env.SUNI_CAPTURE_DIR;

const PAGES = [
  ['Dashboard', 'Tổng quan hệ thống', 'dashboard'],
  ['Người chơi', 'Quản lý người chơi', 'players'],
  ['Sự kiện', 'Quản lý sự kiện', 'events'],
  ['Vật phẩm', 'Quản lý vật phẩm', 'items'],
  ['Giftcode', 'Quản lý giftcode', 'giftcodes'],
  ['Shop', 'Quản lý shop', 'shop'],
  ['Phòng & trận', 'Phòng & trận đấu', 'matches'],
  ['Giao dịch', 'Giao dịch & kinh tế', 'economy'],
  ['Báo cáo', 'Báo cáo', 'reports'],
  ['Server', 'Server', 'server'],
  ['Cài đặt', 'Cài đặt', 'settings'],
];

test.skip(
  !user || !password,
  'SUNI_ADMIN_USER and SUNI_ADMIN_PASSWORD are required',
);

test('admin portal signs in and every module loads without console errors', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 950 });
  const problems = [];
  page.on('console', (message) => {
    // 401 on /auth/login with the wrong password is expected below; behind
    // Cloudflare the injected analytics beacon is blocked by our CSP on purpose.
    const text = message.text();
    if (
      message.type() === 'error' &&
      !text.includes('401') &&
      !text.includes('cloudflareinsights')
    )
      problems.push(text);
  });
  page.on('pageerror', (error) => problems.push(error.message));

  await page.goto('/admin/');
  await expect(page).toHaveURL(/\/admin\/login\/$/);
  await page.getByLabel('Tên đăng nhập').fill(user);
  await page.getByLabel('Mật khẩu').fill('definitely-wrong-password');
  await page.getByRole('button', { name: 'Đăng nhập' }).click();
  await expect(page.locator('.error')).toContainText('không đúng');
  if (capture) await page.screenshot({ path: `${capture}/admin-login.png` });

  await page.getByLabel('Mật khẩu').fill(password);
  await page.getByRole('button', { name: 'Đăng nhập' }).click();
  await expect(page.locator('.topbar h1')).toHaveText('Tổng quan hệ thống');

  for (const [link, heading, shot] of PAGES) {
    await page.locator('.nav').getByRole('link', { name: link }).click();
    await expect(page.locator('.topbar h1')).toHaveText(heading);
    await expect(page.locator('.empty', { hasText: 'Đang tải…' })).toHaveCount(
      0,
    );
    if (capture)
      await page.screenshot({
        path: `${capture}/admin-${shot}.png`,
        fullPage: true,
      });
  }

  await page.locator('.nav').getByRole('link', { name: 'Vật phẩm' }).click();
  await expect(
    page.locator('.card-head h2', { hasText: /\d+ vật phẩm/ }),
  ).toBeVisible();
  expect(await page.locator('tbody tr').count()).toBeGreaterThanOrEqual(18);

  await page.locator('.nav').getByRole('link', { name: 'Người chơi' }).click();
  await expect(page.locator('tbody tr.clickable').first()).toBeVisible();
  await page.locator('tbody tr.clickable').first().click();
  await expect(page.getByRole('dialog')).toBeVisible();
  const dialog = page.getByRole('dialog');
  await dialog.getByRole('button', { name: /Tài sản/ }).click();
  await expect(dialog.locator('.stat').first()).toBeVisible();
  if (capture)
    await page.screenshot({ path: `${capture}/admin-player-assets.png` });
  await dialog.getByRole('button', { name: /Giao dịch/ }).click();
  if (capture)
    await page.screenshot({ path: `${capture}/admin-player-ledger.png` });
  await page.keyboard.press('Escape');
  await expect(page.getByRole('dialog')).toHaveCount(0);

  await page
    .locator('.nav')
    .getByRole('link', { name: 'Phòng & trận' })
    .click();
  if (capture)
    await page.screenshot({
      path: `${capture}/admin-rooms.png`,
      fullPage: true,
    });
  await page.getByRole('button', { name: 'Lịch sử trận' }).click();
  const firstMatch = page.locator('tbody tr.clickable').first();
  await expect(firstMatch).toBeVisible();
  await firstMatch.click();
  await expect(
    page.getByRole('columnheader', { name: 'Hạ gục' }),
  ).toBeVisible();
  if (capture)
    await page.screenshot({
      path: `${capture}/admin-match-history.png`,
      fullPage: true,
    });

  // Mobile width keeps the page inside the viewport.
  await page.setViewportSize({ width: 390, height: 900 });
  await page.locator('.nav').getByRole('link', { name: 'Dashboard' }).click();
  await expect(page.locator('.topbar h1')).toHaveText('Tổng quan hệ thống');
  expect(
    await page.evaluate(
      () => document.documentElement.scrollWidth <= innerWidth + 1,
    ),
  ).toBe(true);
  if (capture)
    await page.screenshot({
      path: `${capture}/admin-mobile.png`,
      fullPage: true,
    });

  await page.getByRole('button', { name: 'Đăng xuất' }).click();
  await expect(page).toHaveURL(/\/admin\/login\/$/);
  expect(problems).toEqual([]);
});
