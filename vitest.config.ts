import { defineConfig } from 'vitest/config';
import * as dotenv from 'dotenv';

// Load the real .env here so tests get the password-bearing DATABASE_URL,
// while the service keys below are forced empty so adapters take their
// deterministic "not configured" path regardless of the local environment.
dotenv.config();

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    include: ['src/**/*.test.ts'],
    env: {
      DOTENV_CONFIG_PATH: '/nonexistent.env',
      SLACK_WEBHOOK_URL: '',
      HUBSPOT_API_KEY: '',
      GOOGLE_SHEET_ID: '',
      GOOGLE_SHEETS_API_KEY: '',
      SEARCH_API_KEY: '',
      DATABASE_URL: process.env.DATABASE_URL || '',
    },
  },
});
