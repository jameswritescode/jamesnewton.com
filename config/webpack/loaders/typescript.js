const PnpWebpackPlugin = require('pnp-webpack-plugin')
const createStyledComponentsTransformer = require('typescript-plugin-styled-components').default

const styledComponentsTransformer = createStyledComponentsTransformer()

module.exports = {
  test: /\.tsx?(\.erb)?$/,
  use: [
    {
      loader: 'ts-loader',
      options: {
        ...PnpWebpackPlugin.tsLoaderOptions(),
        getCustomTransformers: () => ({ before: [styledComponentsTransformer] }),
      },
    },
  ],
}
