import * as React from 'react'
import * as Markdown from 'react-markdown'

import Flex from '~ui/Flex'
import UserContext from '~helpers/user-context'
import { Post as PostType } from '~gql'
import { RENDERERS, PLUGINS } from '~ui/markdown'

import { Header, Code } from '../styles'

type Props = Pick<PostType, 'name' | 'content' | 'created' | 'state'>

export default function Post({ name, content, created, state }: Props) {
  const user = React.useContext(UserContext)

  return (
    <>
      <Header title={name} back>
        <Flex>
          <Code ml={[null, null, '2rem']}>
            {created}
          </Code>

          {user && (
            <Code fontWeight="bold" ml="2rem">
              {state}
            </Code>
          )}
        </Flex>
      </Header>

      <Markdown
        plugins={PLUGINS}
        renderers={RENDERERS}
        source={content}
      />
    </>
  )
}
