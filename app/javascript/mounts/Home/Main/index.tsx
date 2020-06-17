import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'
import { useHomeQuery } from '~gql'

import Code from '../Code'

const Quote = styled.q`
  display: block;
  font-size: 3rem;
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
          url: 'https://jamesnewton.com',
          type: 'profile',
        }}
      />

      <h1>James Newton</h1>

      <blockquote>
        <Quote>{content}</Quote>
        <a href="https://twitter.com/jameswritescode">@jameswritescode</a> {created}
      </blockquote>

      {posts.map(({ id, created, name, url }) => (
        <Flex key={id} alignItems="center">
          <Code mr="1rem">{created}</Code>
          <Link to={url}>{name}</Link>
        </Flex>
      ))}
    </>
  )
}
