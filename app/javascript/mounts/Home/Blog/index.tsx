import * as Markdown from 'react-markdown'
import * as React from 'react'
import styled from 'styled-components'
import { useLocation, Link } from 'react-router-dom'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'
import { usePostQuery } from '~gql'

import Code from '../Code'

const StyledLink = styled(Link)`
  && {
    font-size: 1.2rem;
    margin-right: 2rem;
    text-transform: uppercase;

    :before {
      content: '« ';
    }

    :after {
      content: '';
    }

    @media (max-width: 52em) {
      margin-right: 0;
    }
  }
`

const Header = styled.h1`
  && {
    margin-bottom: 0;
  }

  @media (max-width: 52em) {
    text-align: center;
  }
`

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

      <Flex
        alignItems="center"
        flexDirection={['column', 'column', 'row']}
        mb="2rem"
      >
        <StyledLink to="/">
          Back
        </StyledLink>

        <Header>
          {name}
        </Header>

        <Code ml={[null, null, '2rem']}>
          {created}
        </Code>
      </Flex>

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
