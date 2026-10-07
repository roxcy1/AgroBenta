import { defineConfig } from 'vitest/config'

// Separate from `vite.config.ts` on purpose.
//
// The app is built by Vite 8, whose plugin types are incompatible with the Vite
// copy Vitest resolves for itself, so importing the React plugin here is a
// type error. It is also unnecessary: the tests cover the moderation rules,
// which are pure functions, and nothing under test renders or imports CSS.
//
// Adding a component test later means moving to a DOM environment and bringing
// the React plugin (or Testing Library) in — at which point this file and
// `vite.config.ts` need reconciling on purpose rather than now.
export default defineConfig({
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
})
