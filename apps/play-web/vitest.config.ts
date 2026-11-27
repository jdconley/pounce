import { defineConfig, mergeConfig } from "vitest/config";

import vite from "./vite.config.ts";

export default mergeConfig(
  vite,
  defineConfig({
    test: {
      environment: "node",
      include: ["tests/**/*.test.ts"],
      testTimeout: 30_000,
    },
  }),
);
