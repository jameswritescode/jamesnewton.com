import * as React from 'react'
import { useParams } from 'react-router-dom'

import Head from '~helpers/Head'
import { usePostQuery } from '~gql'

import Post from './Post'
import { Code } from '../styles'

export default function Blog() {
  const { slug } = useParams()
  const { data, loading } = usePostQuery({ variables: { slug } })

  if (loading) return null

  const { post } = data

  if (!post) window.location.assign('/404')

  const { meta, ...postProps } = post

  return (
    <>
      <Head meta={meta} />

      <Post {...postProps} />

      {/* TODO: consider https://creativecommons.org/licenses/by-nc-nd/4.0/ */}
      <Code>
        &copy; 2014-{new Date().getFullYear()} James Newton
      </Code>
    </>
  )
}

Blog.route = '/blog/:slug'
