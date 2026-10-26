import { defineConfig } from '@playwright/test';
const project = process.env.WANI_FONTSOURCE_PROJECT;
if (project && !/^\/[a-zA-Z0-9_./-]+$/.test(project)) throw new Error('Invalid integration project path');
const port = Number(process.env.WANI_TEST_PORT ?? 18000);
if (!Number.isInteger(port) || port < 1 || port > 65535) throw new Error('Invalid WANI_TEST_PORT');
const baseURL = `http://127.0.0.1:${port}`;
export default defineConfig({
  testDir: './test/browser',
  workers: 1,
  timeout: 90_000,
  use: {
    baseURL,
    launchOptions: { ignoreDefaultArgs: ['--disable-popup-blocking'], ...(process.env.CHROMIUM_PATH ? { executablePath: process.env.CHROMIUM_PATH } : {}) },
  },
  webServer: {
    command: `bundle exec ruby -Ilib exe/wani serve ${project ? `${project}/slides.md` : 'test/fixtures/talk/slides.md'} --port ${port}`,
    url: baseURL,
    reuseExistingServer: false,
  },
});
