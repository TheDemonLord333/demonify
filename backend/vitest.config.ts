import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['test/**/*.test.ts'],
    environment: 'node',
    // Integrationstests teilen sich eine Testdatenbank → nacheinander ausführen
    fileParallelism: false,
    testTimeout: 30_000,
    hookTimeout: 60_000,
  },
});
