import { test, expect } from '@playwright/test';
import { mkdir } from 'node:fs/promises';

test.use({
  launchOptions: {
    args: [
      '--use-gl=angle',
      '--use-angle=swiftshader',
      '--enable-unsafe-swiftshader',
    ],
  },
});

test('Step 3 loads its real Godot game, starts maps and accepts keyboard controls', async ({
  browser,
}) => {
  test.setTimeout(120000);
  const context = await browser.newContext({
    viewport: { width: 1440, height: 1080 },
  });
  await context.addInitScript(() => {
    window.practiceAudio = [];
    const Original = window.AudioContext;
    if (Original)
      window.AudioContext = class extends Original {
        constructor(...args) {
          super(...args);
          window.practiceAudio.push(this);
        }
      };
  });
  const page = await context.newPage();
  const errors = [];
  const messages = [];
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => {
    messages.push(message.text());
    if (message.type() === 'error') errors.push(message.text());
  });
  await page.goto('/practice/');
  await expect(
    page.getByRole('heading', { name: 'Một mình bạn, ba đối thủ!' }),
  ).toBeVisible();
  await page.getByRole('button', { name: 'Bắt đầu chơi với bot' }).click();
  await expect
    .poll(() => messages.some((s) => s.includes('PRACTICE_READY')), {
      timeout: 90000,
    })
    .toBe(true);
  const frame = page.frames().find((f) => f.url().includes('/engine/'));
  const canvas = frame.locator('canvas');
  await expect(canvas).toBeVisible();
  const clickGame = async (x, y) => {
    const box = await canvas.boundingBox();
    const scale = Math.min(box.width / 1280, box.height / 920);
    await page.mouse.click(
      box.x + (box.width - 1280 * scale) / 2 + x * scale,
      box.y + (box.height - 920 * scale) / 2 + y * scale,
    );
  };
  await mkdir('docs/screenshots/step3', { recursive: true });
  await page.screenshot({ path: 'docs/screenshots/step3/menu.png' });
  await clickGame(1025, 420); // Kai
  await clickGame(1055, 600); // Coast
  await clickGame(640, 710);
  await expect
    .poll(() =>
      messages.some((s) => s.includes('PRACTICE_ROUND_STARTED coast')),
    )
    .toBe(true);
  await page.keyboard.down('ArrowRight');
  await page.waitForTimeout(350);
  await page.keyboard.up('ArrowRight');
  await page.keyboard.press('Space');
  await page.keyboard.down('ArrowLeft');
  await page.waitForTimeout(200);
  await page.keyboard.up('ArrowLeft');
  await page.keyboard.down('ArrowDown');
  await page.waitForTimeout(400);
  await page.keyboard.up('ArrowDown');
  await page.waitForTimeout(2000);
  await page.screenshot({ path: 'docs/screenshots/step3/gameplay.png' });
  await page.keyboard.press('Escape');
  await page.screenshot({ path: 'docs/screenshots/step3/paused.png' });
  await page.keyboard.press('Escape');
  await page.keyboard.press('m');
  await page.keyboard.press('m');
  await expect
    .poll(() =>
      frame.evaluate(() =>
        window.practiceAudio.some((ctx) => ctx.state === 'running'),
      ),
    )
    .toBe(true);
  await page.keyboard.press('r');
  await expect
    .poll(
      () =>
        messages.filter((s) => s.includes('PRACTICE_ROUND_STARTED coast'))
          .length,
    )
    .toBe(2);
  expect(errors).toEqual([]);
  await context.close();
});
