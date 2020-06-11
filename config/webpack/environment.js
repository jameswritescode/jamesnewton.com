const typescript = require('./loaders/typescript')
const { environment } = require('@rails/webpacker')
const { resolve } = require('path')

const JS_PATH = resolve(__dirname, '..', '..', 'app', 'javascript')

environment.loaders.prepend('typescript', typescript)

environment.config.merge({
  resolve: {
    alias: {
      '~gql': resolve(JS_PATH, 'helpers', 'graphql.ts'),
      '~helpers': resolve(JS_PATH, 'helpers'),
      '~mounts': resolve(JS_PATH, 'mounts'),
    },
  },
})

module.exports = environment
