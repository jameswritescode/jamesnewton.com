import { ApolloClient, InMemoryCache } from '@apollo/client'
import { createUploadLink } from 'apollo-upload-client'
import { setContext } from '@apollo/client/link/context'

// import * as introspectionQueryResultData from '~helpers/fragments.json'

// const fragmentMatcher = new IntrospectionFragmentMatcher({ introspectionQueryResultData })

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

const uploadLink = createUploadLink({ uri: '/graphql' })

export default new ApolloClient({
  cache: new InMemoryCache(/* { fragmentMatcher } */),
  link: authLink.concat(uploadLink as any), // TODO: any because @types/apollo-upload-client is out of date
})
