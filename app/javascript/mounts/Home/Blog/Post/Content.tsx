import * as Markdown from 'react-markdown'
import * as React from 'react'

import Flex from '~ui/Flex'
import UserContext from '~helpers/user-context'
import { RENDERERS, PLUGINS } from '~ui/markdown'

import { Header, Code } from '../../styles'

export default function Content({ name, created, state, content }: any) {
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
