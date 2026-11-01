import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig({
  plugins: [vue()],
  css: {
    // Bootstrap 5.3 internals still use @import, legacy color functions, and Sass if(); silence those warnings from node_modules.
    preprocessorOptions: {
      scss: { silenceDeprecations: ['import', 'global-builtin', 'color-functions', 'if-function'] },
    },
  },
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  server: { host: '0.0.0.0', port: 5173, strictPort: true, allowedHosts: true },
  preview: { host: '0.0.0.0', port: 4173, allowedHosts: true },
  test: {
    environment: 'jsdom',
    include: ['tests/**/*.spec.ts'],
    globals: true,
  },
} as any)
