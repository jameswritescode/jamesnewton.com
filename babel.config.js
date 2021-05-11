module.exports = function(api) {
  const isProductionEnv = api.env('production')

  return {
    presets: ['./node_modules/@rails/webpacker/package/babel/preset.js'],
    plugins: [
      process.env.WEBPACK_DEV_SERVER && 'react-refresh/babel',
      'babel-plugin-styled-components',
      isProductionEnv && [
        'babel-plugin-transform-react-remove-prop-types',
        {
          removeImport: true,
        },
      ],
    ].filter(Boolean),
  }
}
