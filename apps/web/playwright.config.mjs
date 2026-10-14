import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './tests/browser',
  timeout: 60000,
  workers: 1,
  retries: 0,
  outputDir: '../../build/web-test-results',
  use: {
    baseURL: process.env.SUNI_WEB_URL || 'http://127.0.0.1:8081',
    headless: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
});
