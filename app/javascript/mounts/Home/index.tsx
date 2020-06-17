import * as React from 'react'
import { BrowserRouter, Link, Route, Switch } from 'react-router-dom'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'
import Layout from '~ui/Layout'
import { usePostsQuery } from '~gql'

import Blog from './Blog'
import Code from './Code'

export default function Home() {
  const { data } = usePostsQuery()

  if (!data) return null

  return (
    <Layout>
      <BrowserRouter>
        <Switch>
          <Route path="/blog/:slug">
            <Blog />
          </Route>

          <Route path="/">
            <Head
              meta={{
                description: 'James Newton is a software engineer in Seattle',
                title: 'James Newton',
                url: 'https://jamesnewton.com',
                type: 'profile',
              }}
            />

            <h1>James Newton</h1>

            {data.posts.map(({ id, created, name, url }) => (
              <Flex key={id} alignItems="center">
                <Code mr="1rem">{created}</Code>
                <Link to={url}>{name}</Link>
              </Flex>
            ))}
          </Route>
        </Switch>
      </BrowserRouter>
    </Layout>
  )
}
