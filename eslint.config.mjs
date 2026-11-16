import js from "@eslint/js";
import importX from "eslint-plugin-import-x";
import globals from "globals";
import tseslint from "typescript-eslint";

import webMainThread from "./apps/play-web/eslint.main-thread.mjs";

export default tseslint.config(
  {
    // Keep in step with .gitignore.
    ignores: ["**/dist/**", "**/node_modules/**", "**/.wrangler/**", "**/coverage/**", "apps/play-ios/**", "apps/play-api/public/play/**", "apps/play-web/test-results/**", "apps/play-web/playwright-report/**"]
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  {
    files: ["**/*.{ts,tsx,js,mjs}"],
    languageOptions: {
      ecmaVersion: "latest",
      sourceType: "module",
      globals: {
        ...globals.browser,
        ...globals.node
      }
    },
    plugins: {
      "import-x": importX
    },
    rules: {
      "import-x/order": [
        "error",
        {
          alphabetize: { order: "asc", caseInsensitive: true },
          "newlines-between": "always",
          groups: ["builtin", "external", "internal", "parent", "sibling", "index", "object", "type"]
        }
      ]
    }
  },
  // The web player's rendering thread does UI work only (docs/main-thread.md).
  ...webMainThread
);
