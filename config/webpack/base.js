const { webpackConfig, merge } = require('@rails/webpacker')
const { resolve } = require('path')

const JS_PATH = resolve(__dirname, '..', '..', 'app', 'javascript')

const customConfig = {
  module: {
    rules: [
      {
        test: /\.graphql$/,
        use: ['graphql-tag/loader'],
      },
    ],
  },

  resolve: {
    alias: {
      '~gql': resolve(JS_PATH, 'helpers', 'graphql.ts'),
      '~helpers': resolve(JS_PATH, 'helpers'),
      '~mounts': resolve(JS_PATH, 'mounts'),
      '~ui': resolve(JS_PATH, 'ui'),
    },
  },
}

module.exports = merge(webpackConfig, customConfig)
