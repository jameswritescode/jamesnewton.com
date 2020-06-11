import { ApolloClient } from 'apollo-client'
import { InMemoryCache/* , IntrospectionFragmentMatcher */ } from 'apollo-cache-inmemory'
import { createHttpLink } from 'apollo-link-http'
import { setContext } from 'apollo-link-context'

// import * as introspectionQueryResultData from '~helpers/fragments.json'

// const fragmentMatcher = new IntrospectionFragmentMatcher({ introspectionQueryResultData })

const httpLink = createHttpLink({
  uri: '/graphql',
})

const authLink = setContext((_, { headers }) => {
  const token = document
    .querySelector('meta[name=csrf-token]')
    .getAttribute('content')

  return {
    headers: {
      'X-CSRF-Token': token,
      ...headers,
    },
  }
})

export default new ApolloClient({
  cache: new InMemoryCache(/* { fragmentMatcher } */),
  link: authLink.concat(httpLink),
})
