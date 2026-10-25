import { defineConfig } from '@playwright/test';
export default defineConfig({
  testDir: './test/browser',
  workers: 1,
  timeout: 90_000,
  use: {
    baseURL: 'http://127.0.0.1:8000',
    launchOptions: { ignoreDefaultArgs: ['--disable-popup-blocking'], ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}) },
  },
  webServer: {
    command: 'bundle exec ruby -Ilib exe/wani serve test/fixtures/talk/slides.md --port 8000',
    url: 'http://127.0.0.1:8000/',
    reuseExistingServer: false,
  },
});
