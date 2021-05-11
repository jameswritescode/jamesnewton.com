import * as React from 'react'

import Markdown from '~ui/markdown'
import UserContext from '~helpers/user-context'
import { Flex } from '~ui/Elements'

import { Header, Code } from '../../styles'

export default function Content({ name, created, state, content }: any) {
  const user = React.useContext(UserContext)

  return (
    <>
      <Header title={name} back>
        <Flex>
          <Code>
            {created}
          </Code>

          {user && (
            <Code fontWeight="bold" ml="2rem">
              {state}
            </Code>
          )}
        </Flex>
      </Header>

      <Markdown content={content} />
    </>
  )
}
