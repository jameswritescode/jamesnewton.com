import js from "@eslint/js";
import { defineConfig } from "eslint/config";
import pluginPrettier from "eslint-config-prettier/flat";
import pluginImport from "eslint-plugin-import";
import pluginReact from "eslint-plugin-react";
import pluginReactHooks from "eslint-plugin-react-hooks";
import globals from "globals";
import tseslint from "typescript-eslint";

export default defineConfig([
  {
    files: ["**/*.{js,mjs,cjs,ts,mts,cts,jsx,tsx}"],
    plugins: { js },
    extends: ["js/recommended"],
    languageOptions: { globals: globals.browser },
  },
  { ignores: ["app/frontend/routes/*"] },
  {
    settings: {
      react: {
        version: "detect",
      },
    },
    languageOptions: {
      globals: { ...globals.browser, ...globals.node },
      parserOptions: {
        projectService: true,
        tsconfigRootDir: import.meta.dirname,
      },
    },
  },
  {
    ...pluginImport.flatConfigs.recommended,
    ...pluginImport.flatConfigs.typescript,
    ...pluginImport.flatConfigs.react,
    settings: { "import/resolver": { typescript: {} } },
    rules: {
      "import/order": [
        "error",
        {
          pathGroups: [
            {
              pattern: "@/**",
              group: "external",
              position: "after",
            },
          ],
          "newlines-between": "always",
          named: true,
          alphabetize: { order: "asc" },
        },
      ],
      "import/first": "error",
      "import/extensions": [
        "error",
        "always",
        {
          js: "never",
          jsx: "never",
          ts: "never",
          tsx: "never",
        },
      ],
      "@typescript-eslint/consistent-type-imports": "error",
    },
  },
  ...tseslint.configs.recommendedTypeChecked,
  ...tseslint.configs.stylisticTypeChecked,
  pluginReact.configs.flat.recommended,
  pluginReact.configs.flat["jsx-runtime"],
  pluginReactHooks.configs.flat.recommended,
  pluginPrettier,
  {
    files: ["**/*.js", "eslint.config.ts"],
    ...tseslint.configs.disableTypeChecked,
  },
]);
