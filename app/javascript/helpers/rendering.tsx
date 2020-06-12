import * as React from 'react'
import { ApolloProvider } from '@apollo/react-hooks'
import { ThemeProvider } from 'styled-components'
import * as ReactDOM from 'react-dom'

import client from '~helpers/apollo-client'
import { light } from '~ui/theme'

export function withProviders(WrappedComponent: React.ComponentType) {
  function WithProviders() {
    return (
      <ApolloProvider client={client}>
        <ThemeProvider theme={light}>
          <WrappedComponent />
        </ThemeProvider>
      </ApolloProvider>
    )
  }

  WithProviders.displayName = `WithProviders(${WrappedComponent.displayName})`

  return WithProviders
}

export function mount(Component: React.ComponentType) {
  document.addEventListener('DOMContentLoaded', () => {
    ReactDOM.render(
      <Component />,
      document.body.appendChild(document.createElement('div')),
    )
  })
}
