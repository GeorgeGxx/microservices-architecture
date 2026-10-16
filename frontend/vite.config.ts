import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import tailwindcss from '@tailwindcss/vite';
import path from 'path';

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
  ],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  server: {
    port: 5173,
    host: '0.0.0.0',
    proxy: {
      '/graphql': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      '/api/notifications': {
        target: 'http://localhost:8002',
        changeOrigin: true,
      },
      '/api/product': {
        target: 'http://localhost:8004',
        changeOrigin: true,
      },
      '/api/inventory': {
        target: 'http://localhost:8001',
        changeOrigin: true,
      },
      '/api/forecast': {
        target: 'http://localhost:8005',
        changeOrigin: true,
      },
      '/api/order': {
        target: 'http://localhost:8003',
        changeOrigin: true,
      },
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
    chunkSizeWarningLimit: 1000,
    rollupOptions: {
      output: {
        manualChunks: {
          'vendor-react': ['react', 'react-dom'],
          'vendor-icons': ['lucide-react'],
          'vendor-auth': ['keycloak-js'],
        },
      },
    },
  },
  test: {
    globals: true,
    environment: 'node',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'lcov', 'json'],
      include: ['src/**'],
      exclude: [
        'src/main.tsx',
        'src/App.tsx',
        'src/index.css',
        'src/pages/**',
        'src/components/**',
        'src/context/**',
        'src/domain/repositories/**',
        'src/types/**',
        'src/vite-env.d.ts',
        '**/*.test.ts',
        '**/*.test.tsx',
      ],
    },
  },
});
