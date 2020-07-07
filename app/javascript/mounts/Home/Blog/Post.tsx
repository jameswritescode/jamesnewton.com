import * as React from 'react'
import * as Markdown from 'react-markdown'

import { Post as PostType } from '~gql'
import { RENDERERS, PLUGINS } from '~helpers/markdown'

import { Header, Code } from '../styles'

type Props = Pick<PostType, 'name' | 'content' | 'created'>

export default function Post({ name, content, created }: Props) {
  return (
    <>
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
    </>
  )
}
