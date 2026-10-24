import { test, expect } from '@playwright/test';

test.use({
  launchOptions: {
    args: [
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
    ],
  },
});

// /demo/ is the PC app's own Godot build (apps/practice) in a page: launch
// screen, guest entry, PC lobby, practice room and a match with the PC HUD.
test('the web demo runs the PC app: guest, lobby, practice match', async ({
  browser,
}) => {
  test.setTimeout(180000);
  const context = await browser.newContext({
    viewport: { width: 1600, height: 900 },
  });
  const page = await context.newPage();
  const errors = [];
  const messages = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    messages.push(message.text());
    // Software WebGL in CI warns about MSAA; that is not an app error.
    if (
      message.type() === 'error' &&
      !/MSAA|texture_storage/.test(message.text())
    )
      errors.push(message.text());
  });
  const seen = (text, timeout = 60000) =>
    expect
      .poll(() => messages.some((s) => s.includes(text)), { timeout })
      .toBe(true);
  // The software renderer runs at a few frames per second: hold each click
  // long enough for a frame to see both the press and the release.
  const click = async (x, y) => {
    await page.mouse.move(x, y);
    await page.mouse.down();
    await page.waitForTimeout(400);
    await page.mouse.up();
  };

  await page.goto('/practice/');
  await expect(page).toHaveURL(/\/demo\/$/);
  await expect(page.locator('#game')).toHaveAttribute(
    'src',
    '/practice/engine/index.html',
  );
  await seen('PRACTICE_LAUNCH_READY', 120000);
  if (process.env.SUNI_CAPTURE_DIR)
    await page.screenshot({
      path: `${process.env.SUNI_CAPTURE_DIR}/demo-launch.png`,
    });

  await click(960, 711); // CHƠI THỬ (guest)
  await seen('PRACTICE_READY');
  await page.waitForTimeout(3000);
  if (process.env.SUNI_CAPTURE_DIR)
    await page.screenshot({
      path: `${process.env.SUNI_CAPTURE_DIR}/demo-lobby.png`,
    });

  await click(1096, 213); // LUYỆN TẬP
  await page.waitForTimeout(2500);
  await click(416, 370); // Công Viên Kẹo
  await page.waitForTimeout(8000); // bots take their seats and get ready
  await click(1380, 820); // BẮT ĐẦU
  await seen('PRACTICE_ROUND_STARTED park');
  await page.keyboard.down('ArrowRight');
  await page.waitForTimeout(400);
  await page.keyboard.up('ArrowRight');
  await page.keyboard.press('Space');
  await page.waitForTimeout(2000);
  if (process.env.SUNI_CAPTURE_DIR)
    await page.screenshot({
      path: `${process.env.SUNI_CAPTURE_DIR}/demo-match.png`,
    });
  expect(errors).toEqual([]);
  await context.close();
});
