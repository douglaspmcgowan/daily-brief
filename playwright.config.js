// @ts-check
const { defineConfig, devices } = require('@playwright/test');

/** Serves the already-rendered digest on its own port so it never collides with `npm start`. */
module.exports = defineConfig({
  testDir: './tests',
  timeout: 90_000,
  reporter: [['list']],
  use: { baseURL: 'http://127.0.0.1:8788' },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: `python -m http.server 8788 --bind 127.0.0.1 --directory ${__dirname}`,
    reuseExistingServer: false,
    url: 'http://127.0.0.1:8788/index.html',
    timeout: 60_000,
  },
});
