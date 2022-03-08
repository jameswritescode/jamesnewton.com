module.exports = function(api) {
  const isProductionEnv = api.env('production')

  return {
    presets: [
      '@babel/preset-env',
      '@babel/preset-react',
      '@babel/preset-typescript',
    ],
    plugins: [
      process.env.NODE_ENV === 'development' && 'react-refresh/babel',
      'babel-plugin-styled-components',
      isProductionEnv && [
        'babel-plugin-transform-react-remove-prop-types',
        {
          removeImport: true,
        },
      ],
      '@babel/plugin-transform-runtime',
    ].filter(Boolean),
  }
}
