import * as React from 'react'
import styled from 'styled-components'

import Layout from '~ui/layouts/Blog'
import { usePostsQuery } from '~gql'

const Code = styled.code`
  font-size: 1rem;
  position: relative;
  top: -3px;
`

export default function Home() {
  const { data } = usePostsQuery()

  if (!data) return null

  return (
    <Layout>
      <h1>James Newton</h1>

      {data.posts.map(({ id, created, name, url }) => (
        <p key={id}>
          <Code>{created}</Code>
          {' '}
          <a href={url}>{name}</a>
        </p>
      ))}
    </Layout>
  )
}
