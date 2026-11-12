import { defineConfig } from 'vitest/config';
export default defineConfig({
  test: {
    environment: 'jsdom',
    testTimeout: 20000,
    env: { VITE_LIVE: 'true', VITE_API_URL: process.env.API ?? 'http://127.0.0.1:3000' },
  },
});
