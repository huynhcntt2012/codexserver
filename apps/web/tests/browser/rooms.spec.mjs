import { test, expect } from '@playwright/test';
import { mkdir } from 'node:fs/promises';

for (const width of [1440, 390]) {
  test(`room thumbnails form a grid at ${width}px and keep selection accessible`, async ({
    page,
  }) => {
    await page.setViewportSize({ width, height: 1000 });
    let rooms = Array.from({ length: 6 }, (_, i) => ({
      roomId: `garden-${i + 1}`,
      players: i === 5 ? 8 : i + 1,
      maxPlayers: 8,
      ready: 0,
      joinable: i !== 5,
    }));
    await page.route('**/api/v1/login', (route) =>
      route.fulfill({
        json: { access_token: 'fixture', name: 'grid_test', expires_in: 3600 },
      }),
    );
    await page.route('**/arena/rooms', (route) =>
      route.fulfill({ json: { rooms } }),
    );
    await page.goto('/classic/');
    await page.locator('#username').fill('grid_test');
    await page.locator('#password').fill('test-password');
    await page.locator('#join').click();
    const tiles = page.locator('.room-tile');
    await expect(tiles).toHaveCount(6);
    const a = await tiles.nth(0).boundingBox();
    const b = await tiles.nth(1).boundingBox();
    expect(Math.abs(a.y - b.y)).toBeLessThan(1);
    expect(b.x).toBeGreaterThan(a.x);
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth,
      ),
    ).toBe(true);
    await expect(tiles.last()).toBeDisabled();
    await expect(tiles.first()).toContainText('Phòng garden-1');
    expect(
      await tiles
        .first()
        .locator('img')
        .evaluate((img) => img.complete && img.naturalWidth > 0),
    ).toBe(true);
    await tiles.first().focus();
    await page.locator('#refresh-rooms').evaluate((button) => button.click());
    await expect(tiles.first()).toBeFocused();
    await mkdir('docs/screenshots/rooms', { recursive: true });
    await page.screenshot({
      path: `docs/screenshots/rooms/web-${width}.png`,
      fullPage: true,
    });
    const request = page.waitForRequest('**/arena/matchmake/joinById/garden-1');
    await page.route('**/arena/matchmake/joinById/garden-1', (route) =>
      route.fulfill({ status: 404, json: { error: 'room closed' } }),
    );
    await page.keyboard.press('Enter');
    await request;
    await expect(tiles.first()).toBeEnabled();
    rooms = [];
    await page.locator('#refresh-rooms').click();
    await expect(tiles).toHaveCount(0);
    await expect(page.locator('#rooms-empty')).toBeVisible();
  });
}
