import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'
import { useHomeQuery } from '~gql'

import * as POSTS_QUERY from '../Blog/Archive/Posts.graphql'
import PostLine from '../PostLine'
import { Header } from '../styles'

const Quote = styled.q`
  display: block;
  font-size: 1.3em;

  @media (max-width: 52em) {
    font-size: inherit;
  }
`

const A = styled.a`
  margin-left: 1rem;
`

export default function Main() {
  const { client, data } = useHomeQuery()

  if (!data) return null

  const { posts, latestTweet: { content, created } } = data

  return (
    <>
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
        <a href="https://www.sharegrid.com">ShareGrid</a>
      </p>

      <blockquote>
        <Quote dangerouslySetInnerHTML={{ __html: content }} />

        <a href="https://twitter.com/jameswritescode">@jameswritescode</a> {created}
      </blockquote>

      {!!posts.length && (
        <Flex mb="2rem" flexDirection="column">
          {posts.map(({ id, ...post }) => <PostLine key={id} {...post} />)}

          <Flex fontSize="0.8em">
            <Link
              to="/blog"
              onMouseOver={() => client.query({ query: POSTS_QUERY })}
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
    </>
  )
}

Main.route = '/'
