// @ts-check
const { defineConfig, devices } = require('@playwright/test');

const PORT = process.env.DIGEST_TEST_PORT || 8788;

/** Serves the already-rendered digest on its own port so it never collides with `npm start`. */
module.exports = defineConfig({
  testDir: './tests',
  timeout: 90_000,
  reporter: [['list']],
  use: { baseURL: `http://127.0.0.1:${PORT}` },
  projects: [{ name: 'chromium', use: { ...devices['Desktop Chrome'] } }],
  webServer: {
    command: `python -m http.server ${PORT} --bind 127.0.0.1 --directory ${__dirname}`,
    reuseExistingServer: false,
    url: `http://127.0.0.1:${PORT}/index.html`,
    timeout: 60_000,
  },
});
