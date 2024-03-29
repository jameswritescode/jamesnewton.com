import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'

import Head from '~helpers/Head'
import { Flex } from '~ui/Elements'
import { useHomeQuery, PostsDocument } from '~gql'

import PostLine from '../PostLine'
import { Header, Container } from '../styles'

const A = styled.a`
  margin-left: 1rem;
`

export default function Main() {
  const { client, data } = useHomeQuery()

  if (!data) return null

  const { posts } = data

  return (
    <Container>
      <Head
        meta={{
          description: 'James Newton is a Software Engineer in Seattle',
          title: 'James Newton',
          type: 'profile',
          url: 'https://jamesnewton.com',
        }}
      />

      <Header />

      <p>
        I&lsquo;m a Software Engineer in Seattle, WA building{' '}
        <a href="https://www.shopify.com">Shopify</a>
      </p>

      {!!posts.length && (
        <Flex mb="2rem" flexDirection="column">
          {posts.map(({ id, ...post }) => <PostLine key={id} {...post} />)}

          <Flex fontSize="0.8em">
            <Link
              to="/blog"
              onMouseOver={() => client.query({ query: PostsDocument })}
            >
              Archive
            </Link>
          </Flex>
        </Flex>
      )}

      <Flex>
        <Link to="/resume">
          Resume
        </Link>

        <A href="https://github.com/jameswritescode">
          GitHub
        </A>
      </Flex>
    </Container>
  )
}

Main.route = '/'
