process.env.NODE_ENV = process.env.NODE_ENV || 'development'

const webpackConfig = require('./base')
const ReactRefreshWebpackPlugin = require('@pmmmwh/react-refresh-webpack-plugin')
const { devServer, merge } = require('@rails/webpacker')

let customConfig = {}

if (process.env.WEBPACK_DEV_SERVER) {
  customConfig = {
    plugins: [
      new ReactRefreshWebpackPlugin({
        overlay: {
          sockPort: devServer.port,
        },
      }),
    ],
  }
}

module.exports = merge(webpackConfig, customConfig)
