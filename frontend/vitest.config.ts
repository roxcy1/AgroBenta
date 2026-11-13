import { defineConfig } from 'vitest/config'

// Separate from `vite.config.ts` on purpose.
//
// The app is built by Vite 8, whose plugin types are incompatible with the Vite
// copy Vitest resolves for itself, so importing the React plugin here is a
// type error. The default Node environment suits pure tests; React component
// tests opt in to jsdom through their file-level environment directive.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.{ts,tsx}'],
  },
})
