import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'
import { useHomeQuery } from '~gql'

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

export default function Main() {
  const { data } = useHomeQuery()

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

      {posts.map(({ id, created, name, url }) => (
        <StyledFlex key={id} alignItems="center">
          <StyledCode mr="1rem">
            {created}
          </StyledCode>

          <StyledLink to={url}>
            {name}
          </StyledLink>
        </StyledFlex>
      ))}
    </>
  )
}
