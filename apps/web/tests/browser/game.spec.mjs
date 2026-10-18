import { test, expect } from '@playwright/test';
import { randomBytes } from 'node:crypto';
import { mkdir } from 'node:fs/promises';

test('switching auth forms preserves input entered immediately after navigation', async ({
  page,
  baseURL,
}) => {
  await page.goto(`${baseURL}/demo/`);
  await expect(page.locator('#auth-title')).toHaveText('Đăng nhập');
  await page.evaluate(() => {
    document.getElementById('auth-switch').click();
    document.getElementById('password').value = 'test-only-immediate';
    document.getElementById('confirm').value = 'test-only-immediate';
  });
  await page.evaluate(
    () =>
      new Promise((resolve) =>
        requestAnimationFrame(() => requestAnimationFrame(resolve)),
      ),
  );
  await expect(page.locator('#auth-title')).toHaveText('Tạo tài khoản');
  await expect(page.locator('#password')).toHaveValue('test-only-immediate');
  await expect(page.locator('#confirm')).toHaveValue('test-only-immediate');
  await page.goBack();
  await expect(page.locator('#auth-title')).toHaveText('Đăng nhập');
  await expect(page.locator('#password')).toHaveValue('');
});

test('desktop and mobile browsers authenticate, play a round, and retain account sessions', async ({
  browser,
  baseURL,
}) => {
  const desktop = await browser.newContext({
    viewport: { width: 1440, height: 1100 },
  });
  const mobile = await browser.newContext({
    viewport: { width: 390, height: 844 },
    isMobile: true,
    hasTouch: true,
  });
  const a = await desktop.newPage(),
    b = await mobile.newPage();
  const errors = [];
  for (const page of [a, b]) {
    page.on('pageerror', (error) => errors.push(error.message));
    page.on('console', (message) => {
      if (
        message.type() === 'error' &&
        !message.text().includes('status of 401')
      )
        errors.push(message.text());
    });
  }
  let snapshot;
  a.on('websocket', (ws) =>
    ws.on('framereceived', ({ payload }) => {
      if (Buffer.isBuffer(payload) && payload[0] === 17 && payload[1] === 1)
        snapshot = JSON.parse(payload.subarray(2).toString());
    }),
  );
  const username = 'browser_' + randomBytes(5).toString('hex');
  const password = 'test-only-' + randomBytes(12).toString('hex');
  const screenshots = process.env.SUNI_CAPTURE_DIR || 'build/web-screenshots';
  await mkdir(screenshots, { recursive: true });
  try {
    await a.goto(`${baseURL}/demo/`);
    await b.goto(`${baseURL}/demo/`);
    await expect(a.locator('#join')).toBeEnabled();
    await a.screenshot({ path: `${screenshots}/web-home.png`, fullPage: true });
    await b.screenshot({
      path: `${screenshots}/web-mobile.png`,
      fullPage: true,
    });
    expect(
      await b.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await expect(a.locator('#rooms-panel')).toBeHidden();
    await expect(a.locator('#board')).toBeHidden();
    await a.goto(`${baseURL}/demo/#rooms`);
    await expect(a.locator('#auth-panel')).toBeVisible();
    await a.getByRole('link', { name: 'Đăng ký', exact: true }).click();
    await expect(a).toHaveURL(/#register$/);
    await a.screenshot({
      path: `${screenshots}/web-register.png`,
      fullPage: true,
    });
    await a.locator('#username').fill(username);
    await a.locator('#password').fill(password);
    await a.locator('#confirm').fill('not-the-same-password');
    await a.locator('#join').click();
    await expect(a.locator('#status')).toContainText('chưa khớp');
    await a.locator('#password').fill(password);
    await a.locator('#confirm').fill(password);
    await a.locator('#join').click();
    await expect(a.locator('#rooms-panel')).toBeVisible();
    await expect(a.locator('#play-panel')).toBeHidden();
    await a.locator('#create-room').click();
    await expect(a.locator('#room-panel')).toBeVisible();
    await expect(a.locator('#board')).toBeHidden();
    const roomId = (await a.locator('#room-id').textContent()).split(' / ')[1];
    await b.getByRole('link', { name: 'Đăng ký', exact: true }).tap();
    await b.locator('#username').fill(username + '_b');
    await b.locator('#password').fill(password);
    await b.locator('#confirm').fill(password);
    await b.locator('#join').tap();
    await expect(b.locator('#rooms-panel')).toBeVisible();
    const roomCard = b.locator(`[data-room-id="${roomId}"]`);
    await expect(roomCard).toContainText('1/8');
    await b.screenshot({
      path: `${screenshots}/web-rooms-mobile.png`,
      fullPage: true,
    });
    // Creating a second room must not automatically join the first room.
    await b.locator('#create-room').tap();
    await expect(b.locator('#room-id')).not.toHaveText(`PHÒNG / ${roomId}`);
    await expect(b.locator('#room-panel')).toBeVisible();
    await b.locator('#leave').tap();
    await expect(b.locator('#rooms-panel')).toBeVisible();
    await roomCard.getByRole('button', { name: 'Vào phòng' }).tap();
    await expect(b.locator('#room-panel')).toBeVisible();
    await expect(b.locator('#room-id')).toHaveText(`PHÒNG / ${roomId}`);
    await expect(a.locator('#room-hint')).toContainText('0/2');
    await a.screenshot({
      path: `${screenshots}/web-lobby.png`,
      fullPage: true,
    });
    await a.locator('#ready').click();
    await expect(a.locator('#room-hint')).toContainText('1/2');
    await expect(a.locator('#board')).toBeHidden();
    await b.locator('#ready').tap();
    await expect(a.locator('#room-title')).toHaveText('Trận đấu bắt đầu!', {
      timeout: 10000,
    });
    await a.keyboard.press('ArrowRight');
    await expect
      .poll(() => snapshot?.players.find((p) => p.name === username)?.x)
      .toBe(2);
    // Touch movement uses the same intent protocol as desktop keys.
    await b.locator('[data-action="left"]').tap();
    await expect
      .poll(() => snapshot?.players.find((p) => p.name !== username)?.x)
      .toBe(12);
    await a.screenshot({
      path: `${screenshots}/web-gameplay.png`,
      fullPage: true,
    });
    await b.screenshot({
      path: `${screenshots}/web-mobile-gameplay.png`,
      fullPage: true,
    });
    await a.keyboard.press('Space');
    await expect.poll(() => snapshot?.bombs.length).toBe(1);
    await expect(a.locator('#room-title')).toHaveText('Kết quả ván đấu', {
      timeout: 6000,
    });
    await expect(b.locator('#overlay-title')).toHaveText('Bạn thắng rồi!');
    await expect(a.locator('#room-title')).toHaveText('Sảnh chờ', {
      timeout: 12000,
    });
    await a.locator('#leave').click();
    await expect(a.locator('#rooms-list .room-card')).toHaveCount(1);
    await a.screenshot({
      path: `${screenshots}/web-rooms.png`,
      fullPage: true,
    });
    await b.locator('#leave').tap();
    await expect(a.locator('#session-name')).toContainText(username);
    expect(
      await a.evaluate(() => [localStorage.length, sessionStorage.length]),
    ).toEqual([0, 0]);
    await expect(a.locator('#rooms-panel')).toBeVisible();
    await expect(a.locator('#board')).toBeHidden();
    await a.locator('#logout').click();
    await a.locator('#password').fill('wrong-password');
    await a.locator('#join').click();
    await expect(a.locator('#status')).toContainText('chưa đúng');
    await a.locator('#password').fill(password);
    await a.locator('#password').press('Enter');
    await expect(a.locator('#rooms-panel')).toBeVisible();
    await a.reload();
    await expect(a.locator('#auth-panel')).toBeVisible();
    await expect(a.locator('#session-panel')).toBeHidden();
    expect(errors).toEqual([]);
  } finally {
    await desktop.close();
    await mobile.close();
  }
});

test('character chooser loads five supplied characters and supports keyboard dismissal', async ({
  page,
  baseURL,
}) => {
  await page.goto(`${baseURL}/demo/`);
  await page.getByRole('button', { name: 'Nhân vật', exact: true }).click();
  const dialog = page.locator('#characters');
  await expect(dialog).toBeVisible();
  await expect(dialog.locator('[data-character]')).toHaveCount(5);
  await page.locator('[data-character="4"]').click();
  await expect(page.locator('[data-character="4"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  expect(
    await dialog
      .locator('img')
      .evaluateAll((images) =>
        images.every((image) => image.complete && image.naturalWidth > 0),
      ),
  ).toBe(true);
  await page.locator('#characters-confirm').click();
  await expect(dialog).toBeHidden();
  await page.locator('#characters-open').click();
  await expect(page.locator('[data-character="4"]')).toHaveAttribute(
    'aria-pressed',
    'true',
  );
  await page.screenshot({
    path: 'build/web-screenshots/web-characters.png',
    fullPage: true,
  });
  await page.keyboard.press('Escape');
  await expect(dialog).toBeHidden();
});
