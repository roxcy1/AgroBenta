import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    watch: {
      // node_modules lives on a named Docker volume; .git and vite's own
      // cache churn constantly. Restricting the watcher avoids needless
      // filesystem polling over the Windows bind mount during hot-reload.
      ignored: ['**/node_modules/**', '**/.git/**'],
    },
  },
})