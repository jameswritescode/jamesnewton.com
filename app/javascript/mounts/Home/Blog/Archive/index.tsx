// @flow

import * as React from 'react'

import Head from 'helpers/Head'
import { usePostsQuery } from '~gql'

import { Header, PostLine } from '../../styles'

export default function Archive() {
  const { data } = usePostsQuery()

  return (
    <>
      <Head
        meta={{
          description: 'James Newton is a Software Engineer in Seattle',
          title: 'Archive | James Newton',
          type: 'article',
          url: 'https://jamesnewton.com/blog',
        }}
      />

      <Header back />

      {data && data.posts.map(({ id, ...post }) => (
        <PostLine key={id} {...post} />
      ))}
    </>
  )
}

Archive.route = '/blog/:slug'