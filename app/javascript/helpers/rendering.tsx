import * as React from 'react'
import * as ReactDOM from 'react-dom'
import * as ReactGA from 'react-ga'
import { ApolloProvider } from '@apollo/react-hooks'
import { ThemeProvider } from 'styled-components'

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
  ReactGA.initialize('UA-43832701-1')
  ReactGA.pageview(window.location.pathname + window.location.search)

  document.addEventListener('DOMContentLoaded', () => {
    ReactDOM.render(
      <Component />,
      document.body.appendChild(document.createElement('div')),
    )
  })
}
