/* functions/.eslintrc.js */
module.exports = {
  root: true,
  env: {
    es6: true,
    node: true,
  },
  extends: [
    "eslint:recommended",
    "plugin:import/errors",
    "plugin:import/warnings",
    "plugin:import/typescript",
    "google",
    "plugin:@typescript-eslint/recommended",
  ],
  parser: "@typescript-eslint/parser",
  parserOptions: {
    project: ["tsconfig.eslint.json"],  // <- usa o tsconfig específico do ESLint
    tsconfigRootDir: __dirname,
    sourceType: "module",
  },
  ignorePatterns: [
    "/lib/**/*",
    "/generated/**/*",
    ".eslintrc.js",        // <- evita analisar o próprio arquivo de config
  ],
  plugins: ["@typescript-eslint", "import"],
  rules: {
    quotes: ["error", "double"],
    "import/no-unresolved": 0,
    indent: ["error", 2],

    // regras relaxadas p/ não travar deploy
    "require-jsdoc": "off",
    "max-len": ["error", { code: 120, ignoreStrings: true, ignoreTemplateLiterals: true }],
    "object-curly-spacing": "off",
    "brace-style": ["error", "1tbs", { allowSingleLine: true }],
    "one-var": "off",
    "no-multi-spaces": "off",
    "@typescript-eslint/no-explicit-any": "off",
    "@typescript-eslint/no-non-null-assertion": "off",
  },
};
