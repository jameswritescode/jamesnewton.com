import * as Markdown from 'react-markdown'
import * as React from 'react'
import { useLocation } from 'react-router-dom'

import Head from '~helpers/Head'
import { usePostQuery } from '~gql'

import { Header, Code } from '../styles'

function CodeBlock({ value }: { value: string }) {
  return <pre>{value}</pre>
}

function Image(props: any) {
  return <img loading="lazy" {...props} />
}

export default function Blog() {
  const { pathname } = useLocation()
  const parts = pathname.split('/')
  const slug = parts[parts.length - 1]

  const { data, loading } = usePostQuery({ variables: { slug } })

  if (loading) return null

  const { post } = data

  if (!post) window.location.assign('/404')

  const { name, content, created, meta } = post

  const renderers = {
    code: CodeBlock,
    image: Image,
    imageReference: Image,
  }

  return (
    <>
      <Head meta={meta} />

      <Header title={name} back>
        <Code ml={[null, null, '2rem']}>
          {created}
        </Code>
      </Header>

      <Markdown
        source={content}
        renderers={renderers}
      />

      {/* TODO: consider https://creativecommons.org/licenses/by-nc-nd/4.0/ */}
      <Code>
        &copy; 2014-{new Date().getFullYear()} James Newton
      </Code>
    </>
  )
}
