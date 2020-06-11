import * as React from 'react'
import * as ReactDOM from 'react-dom'
import { ApolloProvider } from '@apollo/react-hooks'
import { hot } from 'react-hot-loader/root'

import Home from '~mounts/Home'
import client from '~helpers/apollo-client'

let Component = () => (
  <ApolloProvider client={client}>
    <Home />
  </ApolloProvider>
)

Component = hot(Component)

document.addEventListener('DOMContentLoaded', () => {
  ReactDOM.render(
    <Component />,
    document.body.appendChild(document.createElement('div')),
  )
})
