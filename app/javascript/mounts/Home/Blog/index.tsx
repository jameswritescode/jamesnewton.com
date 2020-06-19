import * as Markdown from 'react-markdown'
import * as React from 'react'
import { useParams } from 'react-router-dom'

import Head from '~helpers/Head'
import { usePostQuery } from '~gql'

import { Header, Code } from '../styles'
import { RENDERERS, PLUGINS } from './remark'

export default function Blog() {
  const { slug } = useParams()
  const { data, loading } = usePostQuery({ variables: { slug } })

  if (loading) return null

  const { post } = data

  if (!post) window.location.assign('/404')

  const { name, content, created, meta } = post

  return (
    <>
      <Head meta={meta} />

      <Header title={name} back>
        <Code ml={[null, null, '2rem']}>
          {created}
        </Code>
      </Header>

      <Markdown
        plugins={PLUGINS}
        renderers={RENDERERS}
        source={content}
      />

      {/* TODO: consider https://creativecommons.org/licenses/by-nc-nd/4.0/ */}
      <Code>
        &copy; 2014-{new Date().getFullYear()} James Newton
      </Code>
    </>
  )
}
