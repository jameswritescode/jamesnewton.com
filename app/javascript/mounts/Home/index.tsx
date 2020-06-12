import * as React from 'react'

import Layout from '~ui/layouts/Blog'
import { usePostsQuery } from '~gql'

export default function Home() {
  const { data } = usePostsQuery()

  if (!data) return null

  return (
    <Layout>
      <h1>James Newton</h1>

      {data.posts.map(({ id, name }) => (
        <p key={id}>
          {name}
        </p>
      ))}
    </Layout>
  )
}
