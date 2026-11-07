import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Die Verwaltung läuft unter https://demonify.thedemonlord333.me/admin/
export default defineConfig({
  base: '/admin/',
  plugins: [react()],
  server: {
    port: 5173,
    // Entwicklung: API-Aufrufe relativ unter /api/v1 an das lokale Backend weiterleiten
    proxy: { '/api': { target: 'http://127.0.0.1:1340', changeOrigin: false } },
  },
  build: { outDir: 'dist', sourcemap: false, assetsDir: 'assets' },
});
