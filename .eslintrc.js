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
    'space-before-function-paren': ['error', 'never'],

    // eslint-plugin-graphql
    'graphql/template-strings': ['error',
      {
        env: 'literal',
        schemaJson: require('./schema.json'),
      },
      {
        env: 'apollo',
        schemaJson: require('./schema.json'),
      },
    ],

    'graphql/required-fields': ['error',
      {
        env: 'literal',
        schemaJson: require('./schema.json'),
        requiredFields: ['id'],
      },
      {
        env: 'apollo',
        schemaJson: require('./schema.json'),
        requiredFields: ['id'],
      },
    ],
  },
}
