// @flow

import * as React from 'react'

import { usePostsQuery } from '~gql'

import { Header, PostLine } from '../styles'

export default function Archive() {
  const { data } = usePostsQuery()

  return (
    <>
      <Header back />

      {data && data.posts.map(({ id, ...post }) => (
        <PostLine key={id} {...post} />
      ))}
    </>
  )
}
