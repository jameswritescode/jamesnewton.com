import * as Markdown from 'react-markdown'
import * as React from 'react'
import styled from 'styled-components'
import { useLocation, Link } from 'react-router-dom'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'
import Layout from '~ui/Layout'
import { usePostQuery } from '~gql'

import Code from '../Code'

const StyledLink = styled(Link)`
  && {
    font-size: 2em;
    line-height: 1;
    margin-right: 2rem;
    position: relative;
    top: -4px;

    :after {
      content: '';
    }

    @media (max-width: 52em) {
      margin-right: 0;
      top: 0;
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

  const { data } = usePostQuery({ variables: { slug } })

  if (!data) return null

  const { name, content, created, meta } = data.post

  const renderers = {
    code: CodeBlock,
    image: Image,
    imageReference: Image,
  }

  return (
    <Layout>
      <Head meta={meta} />

      <Flex
        alignItems="center"
        flexDirection={['column', 'column', 'row']}
        mb="2rem"
      >
        <StyledLink to="/">
          «
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
    </Layout>
  )
}
