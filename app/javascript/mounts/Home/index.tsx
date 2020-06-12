import * as React from 'react'
import { BrowserRouter, Link, Route, Switch } from 'react-router-dom'

import Flex from '~ui/Flex'
import Layout from '~ui/Layout'
import { usePostsQuery } from '~gql'

import Blog from './Blog'
import Code from './Code'

export default function Home() {
  const { data } = usePostsQuery()

  if (!data) return null

  return (
    <BrowserRouter>
      <Switch>
        <Route path="/blog/:slug">
          <Blog />
        </Route>

        <Route path="/">
          <Layout>
            <h1>James Newton</h1>

            {data.posts.map(({ id, created, name, url }) => (
              <Flex key={id} alignItems="center">
                <Code mr="1rem">{created}</Code>
                <Link to={url}>{name}</Link>
              </Flex>
            ))}
          </Layout>
        </Route>
      </Switch>
    </BrowserRouter>
  )
}
