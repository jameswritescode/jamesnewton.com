import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'
import { useHomeQuery } from '~gql'

import * as POST_QUERY from '../Blog/Post.graphql'
import { Code, Header } from '../styles'

const StyledCode = styled(Code)`
  white-space: nowrap;
`

const Quote = styled.q`
  display: block;
  font-size: 1.3em;

  @media (max-width: 52em) {
    font-size: inherit;
  }
`

const StyledFlex = styled(Flex)`
  white-space: nowrap;
`

const StyledLink = styled(Link)`
  overflow-x: hidden;
  text-overflow: ellipsis;
`

const A = styled.a`
  margin-left: 1rem;
`

export default function Main() {
  const { data, client } = useHomeQuery()

  if (!data) return null

  const { posts, latestTweet: { content, created } } = data

  return (
    <>
      <Head
        meta={{
          description: 'James Newton is a software engineer in Seattle',
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
          {posts.map(({ id, created, name, url, slug }) => (
            <StyledFlex key={id} alignItems="center">
              <StyledCode mr="1rem">
                {created}
              </StyledCode>

              <StyledLink
                onMouseOver={() => client.query({ query: POST_QUERY, variables: { slug } })}
                to={url}
              >
                {name}
              </StyledLink>
            </StyledFlex>
          ))}
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
