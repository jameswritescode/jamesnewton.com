import * as React from 'react'
import { useParams } from 'react-router-dom'

import Head from '~helpers/Head'
import { usePostQuery } from '~gql'

import Content from './Content'
import { Code } from '../../styles'

export default function Post() {
  const { slug } = useParams()
  const { data, loading } = usePostQuery({ variables: { slug } })

  if (loading) return null

  const { post } = data

  if (!post) window.location.assign('/404')

  const { meta, ...rest } = post

  return (
    <>
      <Head meta={meta} />

      <Content {...rest} />

      {/* TODO: consider https://creativecommons.org/licenses/by-nc-nd/4.0/ */}
      <Code>
        &copy; 2014-{new Date().getFullYear()} James Newton
      </Code>
    </>
  )
}
