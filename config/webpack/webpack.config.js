const ReactRefreshWebpackPlugin = require('@pmmmwh/react-refresh-webpack-plugin')
const WebpackAssetsManifest = require('webpack-assets-manifest')
const webpack = require('webpack')
const { resolve } = require('path')

const DEV_SERVER_PORT = 3035
const JS_PATH = resolve(__dirname, '..', '..', 'app/javascript')

const isDevelopment = process.env.NODE_ENV === 'development'
const mode = isDevelopment ? 'development' : 'production'
const outputNamePrefix = isDevelopment ? '[name]-[contenthash]' : '[name]'

module.exports = {
  mode,
  devtool: !isDevelopment ? 'source-map' : 'cheap-module-source-map',

  entry: {
    application: './app/javascript/packs/application.ts',
  },

  devServer: {
    compress: true,
    host: 'localhost',
    hot: true,
    port: DEV_SERVER_PORT,

    client: {
      overlay: true,
    },

    headers: {
      'Access-Control-Allow-Origin': '*',
    },

    static: {
      watch: {
        ignored: /node_modules/,
      },
    },
  },

  module: {
    rules: [
      {
        test: /\.(j|t)sx?$/,
        exclude: /node_modules/,
        use: ['babel-loader'],
      },
      {
        test: /\.graphql$/,
        use: ['graphql-tag/loader'],
      },
    ],
  },

  output: {
    filename: `${outputNamePrefix}.js`,
    path: resolve(__dirname, '..', '..', 'app/assets/builds'),
    sourceMapFilename: `${outputNamePrefix}.js.map`,
  },

  plugins: [
    // TODO: Optimize for production?
    !isDevelopment && new webpack.optimize.LimitChunkCountPlugin({ maxChunks: 1 }),

    isDevelopment && new ReactRefreshWebpackPlugin({
      overlay: {
        sockPort: DEV_SERVER_PORT,
      },
    }),

    isDevelopment && new WebpackAssetsManifest({ entrypoints: true }),
  ].filter(Boolean),

  resolve: {
    extensions: ['.js', '.jsx', '.mjs', '.ts', '.tsx'],

    alias: {
      '~gql': resolve(JS_PATH, 'helpers', 'graphql.ts'),
      '~helpers': resolve(JS_PATH, 'helpers'),
      '~mounts': resolve(JS_PATH, 'mounts'),
      '~ui': resolve(JS_PATH, 'ui'),
    },
  },
}
