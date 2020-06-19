import * as React from 'react'
import styled from 'styled-components'

import Flex from '~ui/Flex'
import Head from '~helpers/Head'

import Post from './Blog/Post'

const EditorFlex = styled(Flex)`
  textarea, input {
    border-radius: 3px;
    border: 1px solid ${props => props.theme.primary};
    line-height: 2;
    padding: 2rem;
  }

  input {
    font-size: 2rem;
    font-weight: bold;
    margin-bottom: 2rem;
  }

  textarea {
    height: 100%;
    width: 100%;
  }
`

const PLACEHOLDER_TITLE = 'Placeholder'

const PLACEHOLDER_CONTENT = `# Header
## Header
### Header
#### Header
##### Header
###### Header

::highlighting some text::

*italics* **strong** ***both***

* one
    1. two
* three
* four
    * five

> this is is using a blockquote

\`\`\`ruby
() => {
  console.log("what's good")
}
\`\`\`

1. one
    * two
2. three
3. four
    1. five

![alt](https://placekitten.com/500/500)

This is a paragraph of text using \`code\`

This is another paragraph of text with a [link](#) in it
`

export default function Editor() {
  const [content, setContent] = React.useState('')
  const [title, setTitle] = React.useState('')

  const widths = [1, 1, 1 / 2]
  const margins = [0, 0, '2rem']

  return (
    <>
      <Head
        meta={{
          description: 'Editor',
          title: 'Editor',
          type: '',
          url: window.location.href,
        }}
      />

      <Flex flexDirection={['column', 'column', 'row']}>
        <EditorFlex
          flexDirection="column"
          mb={['2rem', '2rem', 0]}
          mr={margins}
          width={widths}
        >
          <input
            onChange={e => setTitle(e.target.value)}
            placeholder={PLACEHOLDER_TITLE}
            type="text"
          />

          <textarea
            onChange={e => setContent(e.target.value)}
            placeholder={PLACEHOLDER_CONTENT}
            onKeyDown={e => {
              if (e.keyCode === 9) {
                e.preventDefault()

                const currentTarget = e.currentTarget
                const value = currentTarget.value
                const start = currentTarget.selectionStart
                const end = currentTarget.selectionEnd

                currentTarget.value = value.substring(0, start) + '  ' + value.substring(end)
                currentTarget.selectionStart = currentTarget.selectionEnd = start + 2
              }
            }}
          />
        </EditorFlex>

        <Flex
          flexDirection="column"
          ml={margins}
          width={widths}
        >
          <Post
            content={content || PLACEHOLDER_CONTENT}
            created="May 06, 1992"
            name={title || PLACEHOLDER_TITLE}
          />
        </Flex>
      </Flex>
    </>
  )
}
