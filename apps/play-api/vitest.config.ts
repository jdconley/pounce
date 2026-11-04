import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    coverage: {
      provider: "v8",
      include: ["src/**/*.ts"],
      // The Durable Object glue, device index and worker entry run inside
      // Miniflare, whose bundles cannot feed v8 coverage. Integration tests
      // cover them instead.
      exclude: [
        "src/**/*.test.ts",
        "tests/**",
        "src/room/game-room.ts",
        "src/room/device-index.ts",
        "src/players/player.ts",
        "src/players/identities.ts",
        "src/players/accounts.ts",
        "src/index.ts",
      ],
      reporter: ["text", "json-summary"],
      thresholds: {
        statements: 90,
        branches: 90,
        functions: 90,
        lines: 90,
        "src/rules/**": {
          statements: 100,
          branches: 100,
          functions: 100,
          lines: 100,
        },
        "src/room/core.ts": {
          statements: 100,
          branches: 100,
          functions: 100,
          lines: 100,
        },
      },
    },
    environment: "node",
    include: ["src/**/*.test.ts", "tests/**/*.test.ts"],
  },
});
