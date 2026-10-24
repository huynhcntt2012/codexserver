import { readFileSync } from 'node:fs';
import type { Express } from 'express';
import { Marked, Renderer } from 'marked';

const sourceUrl =
  'https://github.com/huynhcntt2012/codexserver/blob/suni/06-client-polish/docs/ARENA.md';
const slug = (text: string) =>
  text
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replaceAll('đ', 'd')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-|-$/g, '');

export function registerDocuments(app: Express) {
  // Only trusted, version-controlled Markdown is rendered, once at startup.
  // Never pass request data or user-authored content to this renderer.
  const markdown = readFileSync(
    new URL('../../../docs/ARENA.md', import.meta.url),
    'utf8',
  );
  const stylesheet = readFileSync(
    new URL('../public/documents.css', import.meta.url),
    'utf8',
  );
  const contents: string[] = [];
  const marked = new Marked({
    renderer: {
      heading({ depth, text, tokens }) {
        const id = slug(text);
        const label = this.parser.parseInline(tokens);
        if (depth === 2)
          contents.push(`<li><a href="#${id}">${label}</a></li>`);
        return `<h${depth} id="${id}">${label}</h${depth}>`;
      },
      table(token) {
        return `<div class="table-scroll" role="region" aria-label="Bảng tham khảo" tabindex="0">${Renderer.prototype.table.call(this, token)}</div>`;
      },
    },
    walkTokens(token) {
      if (token.type === 'link' && !token.href.startsWith('#'))
        token.href = new URL(token.href, sourceUrl).href;
    },
  });
  const body = marked.parse(markdown, { async: false });
  const page = `<!doctype html>
<html lang="vi">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Tính năng, API, WebSocket và hướng dẫn tích hợp server realtime Suni Bomb Arena.">
  <title>Tài liệu realtime — Suni Bomb Arena</title>
  <link rel="stylesheet" href="__STYLESHEET__">
</head>
<body>
  <a class="skip-link" href="#content">Đến nội dung</a>
  <header class="site-header">
    <span class="brand">Suni Bomb Arena <span>Developer docs</span></span>
    <a href="${sourceUrl}">Xem trên GitHub ↗</a>
  </header>
  <div class="layout">
    <nav aria-label="Mục lục"><p class="eyebrow">Server realtime</p><h2>Mục lục</h2><ol>${contents.join('')}</ol></nav>
    <main id="content"><p class="eyebrow">Colyseus · Protocol v1</p>${body}</main>
  </div>
  <footer>Suni Bomb Arena · <a href="#content">Về đầu trang ↑</a></footer>
</body>
</html>`;

  app.get(['/documents', '/documents/'], (req, res) => {
    res.set({
      'Cache-Control': 'no-cache',
      'Content-Security-Policy':
        "default-src 'none'; style-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'",
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
    });
    // Relative paths also work behind the website's /arena/ proxy prefix.
    res
      .type('html')
      .send(
        page.replace(
          '__STYLESHEET__',
          req.path.endsWith('/') ? 'style.css' : 'documents/style.css',
        ),
      );
  });
  app.get('/documents/style.css', (_req, res) => {
    res.set('Cache-Control', 'no-cache').type('css').send(stylesheet);
  });
}
