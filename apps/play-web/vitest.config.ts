import { defineConfig, mergeConfig } from "vitest/config";

import vite from "./vite.config.ts";

export default mergeConfig(
  vite,
  defineConfig({
    // Tests see every game the server has, whatever production's flag says.
    define: { __GAMES__: "undefined" },
    test: {
      environment: "node",
      include: ["tests/**/*.test.ts"],
      testTimeout: 30_000,
    },
  }),
);
