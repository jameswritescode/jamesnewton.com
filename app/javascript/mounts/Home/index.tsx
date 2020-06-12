import * as React from 'react'

import { usePostsQuery } from '~gql'

export default function Home() {
  const { data } = usePostsQuery()

  if (!data) return null

  return (
    <>
      <h1>James Newton</h1>

      {data.posts.map(({ id, name }) => (
        <div key={id}>
          {name}
        </div>
      ))}
    </>
  )
}
