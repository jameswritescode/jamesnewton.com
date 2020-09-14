process.env.NODE_ENV = process.env.NODE_ENV || 'development'

const ReactRefreshWebpackPlugin = require('@pmmmwh/react-refresh-webpack-plugin')
const { devServer } = require('@rails/webpacker')

const environment = require('./environment')

if (process.env.WEBPACK_DEV_SERVER) {
  environment.plugins.append(
    'ReactRefreshWebpackPlugin',
    new ReactRefreshWebpackPlugin({
      overlay: {
        sockPort: devServer.port,
      },
    }),
  )
}

module.exports = environment.toWebpackConfig()
