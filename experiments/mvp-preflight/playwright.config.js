import { defineConfig } from '@playwright/test';
export default defineConfig({
  workers: 1,
  testDir: './test',
  timeout: 120_000,
  use: {
    baseURL: 'http://127.0.0.1:8080',
    launchOptions: { ignoreDefaultArgs: ["--disable-popup-blocking"], ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}) },
  },
  webServer: { command: 'npm run serve', url: 'http://127.0.0.1:8080', reuseExistingServer: false },
});
