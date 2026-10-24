import { test, expect } from '@playwright/test';

// Admin Portal "Website" module end to end on a throwaway stack (it writes: creates,
// publishes and deletes a post, edits then restores the hero). Needs an operator or
// owner: SUNI_ADMIN_USER / SUNI_ADMIN_PASSWORD; optional viewer for the read-only
// check: SUNI_VIEWER_USER / SUNI_VIEWER_PASSWORD. Set SUNI_CAPTURE_DIR for screenshots.
const user = process.env.SUNI_ADMIN_USER;
const password = process.env.SUNI_ADMIN_PASSWORD;
const viewer = process.env.SUNI_VIEWER_USER;
const viewerPassword = process.env.SUNI_VIEWER_PASSWORD;
const capture = process.env.SUNI_CAPTURE_DIR;

test.skip(
  !user || !password,
  'SUNI_ADMIN_USER and SUNI_ADMIN_PASSWORD are required',
);

async function signIn(page, name, secret) {
  await page.goto('/admin/login/');
  await page.getByLabel('Tên đăng nhập').fill(name);
  await page.getByLabel('Mật khẩu').fill(secret);
  await page.getByRole('button', { name: 'Đăng nhập' }).click();
  await expect(page.locator('.topbar h1')).toHaveText('Tổng quan hệ thống');
  await page.locator('.nav').getByRole('link', { name: 'Website' }).click();
  await expect(page.locator('.topbar h1')).toHaveText('Website');
}

function watch(page) {
  const problems = [];
  page.on('console', (message) => {
    const text = message.text();
    if (message.type() === 'error' && !text.includes('cloudflareinsights'))
      problems.push(text);
  });
  page.on('pageerror', (error) => problems.push(error.message));
  return problems;
}

test('operator publishes news and edits the hero shown on the site', async ({
  page,
}) => {
  await page.setViewportSize({ width: 1440, height: 950 });
  const problems = watch(page);
  const stamp = Date.now().toString(36);
  const title = `Kiểm thử CMS ${stamp} <b>không phải HTML</b>`;
  await signIn(page, user, password);

  // Remove the test post and restore the hero even when an assertion fails half way.
  const token = await page.evaluate(() =>
    sessionStorage.getItem('bup-admin-token'),
  );
  const headers = { Authorization: `Bearer ${token}` };
  const heroBefore = (
    await (
      await page.request.get('/admin/api/website/site', { headers })
    ).json()
  ).hero;
  const cleanup = async () => {
    await page.request.put('/admin/api/website/site', {
      headers,
      data: heroBefore,
    });
    const reply = await page.request.get('/admin/api/website/news', {
      headers,
    });
    for (const post of (await reply.json()).news ?? [])
      if (post.slug.includes(stamp))
        await page.request.delete(`/admin/api/website/news/${post.id}`, {
          headers,
        });
  };
  try {
    await flow();
  } finally {
    await cleanup();
  }

  async function flow() {
    // News: write a draft (plain text with markup characters), publish, read it on the site.
    await page.getByRole('button', { name: '+ Viết bài' }).click();
    const dialog = page.getByRole('dialog');
    await dialog.getByLabel('Tiêu đề').fill(title);
    await expect(dialog.getByLabel('Đường dẫn (slug)')).toHaveValue(
      `kiem-thu-cms-${stamp}-b-khong-phai-html-b`,
    );
    await dialog.getByLabel('Danh mục').selectOption('Sự kiện');
    await dialog.getByLabel('Tóm tắt').fill('Tóm tắt bài kiểm thử.');
    await dialog
      .getByLabel('Nội dung')
      .fill('Đoạn một.\n\n<script>window.pwned = 1</script>');
    await dialog.getByLabel('Ghim').check();
    if (capture)
      await page.screenshot({ path: `${capture}/admin-website-editor.png` });
    await dialog.getByRole('button', { name: 'Tạo bản nháp' }).click();
    await expect(dialog).toHaveCount(0);
    const row = page.locator('tbody tr', { hasText: stamp });
    await expect(row.locator('.badge')).toHaveText('Bản nháp');
    await row.getByRole('button', { name: 'Đăng' }).click();
    await expect(row.locator('.badge')).toHaveText('Đã phát hành');
    if (capture)
      await page.screenshot({
        path: `${capture}/admin-website-news.png`,
        fullPage: true,
      });

    const site = await page.context().newPage();
    const siteProblems = watch(site);
    // Old /adminportal links redirect to the site root; the web game is at /demo/
    // (the PC app's web build) and the earlier JS client at /classic/.
    await site.goto('/adminportal/news/');
    await expect(site).toHaveURL(/\/news\/$/);
    await site.goto('/classic/');
    await expect(site.locator('#auth-title')).toHaveText('Đăng nhập');
    await site.goto('/news/');
    const card = site.locator('#news-list .card').first();
    await expect(card.locator('h3')).toHaveText(title);
    await card.click();
    await expect(site.locator('#post h1')).toHaveText(title);
    await expect(site.locator('#post p').nth(1)).toHaveText(
      '<script>window.pwned = 1</script>',
    );
    expect(await site.evaluate(() => window.pwned)).toBeUndefined();

    // Hero: change the texts, check the home page, then restore what was there.
    await page.getByRole('button', { name: 'Banner trang chủ' }).click();
    const headline = page.getByLabel('Tiêu đề', { exact: true });
    await expect(headline).toHaveValue(heroBefore.headline);
    await headline.fill(`Mùa bóng nước ${stamp}`);
    await page.getByLabel('Nút tải game', { exact: true }).fill('Tải bản mới');
    await expect(page.locator('.hero-preview b')).toHaveText(
      `Mùa bóng nước ${stamp}`,
    );
    await page.getByRole('button', { name: 'Lưu banner' }).click();
    await expect(page.locator('.toast')).toHaveText('Đã lưu banner trang chủ');
    if (capture)
      await page.screenshot({ path: `${capture}/admin-website-hero.png` });
    // The public endpoint is cached for 60 s by browsers; bypass it for the check.
    await site.route('**/api/v1/public/site', (route) =>
      route.continue({ headers: { 'Cache-Control': 'no-cache' } }),
    );
    await site.goto('/');
    await expect(site.locator('#hero-title')).toContainText(
      `Mùa bóng nước ${stamp}`,
    );
    await expect(
      site.locator('.hero .hero-cta [data-cta="download"]'),
    ).toHaveText('Tải bản mới');
    await expect(site.locator('#home-news .card h3').first()).toHaveText(title);

    // Downloads: read-only view of latest.json and history.
    await page.getByRole('button', { name: 'Bản tải' }).click();
    await expect(page.locator('.card-head h2').first()).toBeVisible();
    await expect(page.locator('.empty', { hasText: 'Đang tải…' })).toHaveCount(
      0,
    );
    if (capture)
      await page.screenshot({
        path: `${capture}/admin-website-downloads.png`,
        fullPage: true,
      });

    // Clean up the post; it disappears from the site.
    await page.getByRole('button', { name: 'Tin tức' }).click();
    page.once('dialog', (confirm) => confirm.accept());
    await row.getByRole('button', { name: 'Xóa' }).click();
    await expect(row).toHaveCount(0);
    await site.goto('/news/');
    await expect(site.locator('#news-list .card h3').first()).not.toHaveText(
      title,
    );

    // Phone width keeps the admin page inside the viewport.
    await page.setViewportSize({ width: 390, height: 900 });
    expect(
      await page.evaluate(
        () => document.documentElement.scrollWidth <= innerWidth + 1,
      ),
    ).toBe(true);
    expect(problems).toEqual([]);
    expect(siteProblems).toEqual([]);
  }
});

test('viewer sees the Website module read-only', async ({ page }) => {
  test.skip(
    !viewer || !viewerPassword,
    'SUNI_VIEWER_USER and SUNI_VIEWER_PASSWORD are required',
  );
  const problems = watch(page);
  await signIn(page, viewer, viewerPassword);
  await expect(page.locator('tbody tr').first()).toBeVisible();
  await expect(page.getByRole('button', { name: '+ Viết bài' })).toHaveCount(0);
  await expect(page.getByRole('button', { name: 'Xóa' })).toHaveCount(0);
  await page
    .locator('tbody tr')
    .first()
    .getByRole('button', { name: 'Chi tiết' })
    .click();
  await expect(page.getByRole('dialog').getByLabel('Tiêu đề')).toBeDisabled();
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: 'Banner trang chủ' }).click();
  await expect(page.getByLabel('Tiêu đề', { exact: true })).toBeDisabled();
  await expect(page.getByRole('button', { name: 'Lưu banner' })).toHaveCount(0);
  expect(problems).toEqual([]);
});
