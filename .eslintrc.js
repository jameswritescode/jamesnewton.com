const graphqlSchema = require('./schema.json')

const graphqlSettings = (extra = {}) => [
  'error',
  { env: 'literal', schemaJson: graphqlSchema, ...extra },
  { env: 'apollo', schemaJson: graphqlSchema, ...extra },
]

module.exports = {
  env: {
    browser: true,
    es6: true,
  },

  extends: [
    'plugin:react-hooks/recommended',
    'plugin:react/recommended',
    'standard',
  ],

  globals: {
    Atomics: 'readonly',
    SharedArrayBuffer: 'readonly',
  },

  parser: '@typescript-eslint/parser',

  parserOptions: {
    ecmaFeatures: {
      jsx: true,
    },

    ecmaVersion: 11,
    sourceType: 'module',
  },

  plugins: [
    '@typescript-eslint',
    'graphql',
    'react',
  ],

  rules: {
    'comma-dangle': ['error', 'always-multiline'],
    'no-unused-vars': 'off',
    'space-before-function-paren': ['error', 'never'],

    // typescript-eslint
    '@typescript-eslint/no-unused-vars': ['error'],

    // eslint-plugin-graphql
    'graphql/required-fields': graphqlSettings({ requiredFields: ['id'] }),
    'graphql/template-strings': graphqlSettings(),
  },
}
