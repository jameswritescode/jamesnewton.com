import * as React from 'react'
import styled from 'styled-components'
import { useRouteMatch, useHistory } from 'react-router-dom'

import Button from '~ui/Button'
import Head from '~helpers/Head'
import Layout from '~ui/Layout'
import UserContext from '~helpers/user-context'
import { Flex } from '~ui/Elements'

import {
  PostState,
  useCreateAttachmentMutation,
  usePostQuery,
  useUpdateOrCreatePostMutation,
} from '~gql'

import * as POST_QUERY from '../../Blog/Post/Post.graphql'
import Archive from '../../Blog/Archive'
import Content from '../../Blog/Post/Content'

const EditorFlex = styled(Flex)`
  textarea, input {
    border-radius: 3px;
    border: 1px solid ${props => props.theme.primary};
    line-height: 2;
    margin-bottom: 2rem;
    padding: 2rem;
  }

  input {
    font-size: 2rem;
    font-weight: bold;
  }

  textarea {
    height: 100%;
    resize: vertical;
    width: 100%;
  }

  input, textarea {
    :last-child {
      margin-bottom: 0;
    }
  }
`

const PLACEHOLDER_NAME = 'Placeholder'

const PLACEHOLDER_CONTENT = `# Header
## Header
### Header
#### Header
##### Header
###### Header

::highlighting some text::

*italics* **strong** ***both*** ~~strike~~

Header | Header | Header
------ | ------ | ------
Cell   | Cell   | Cell
Cell   | Cell   | Cell

---

* one
    1. two
* three
* four
    * five

> this is is using a blockquote

\`\`\`javascript
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

type Editor = {
  close: Function,
}

function insertAtCaret(text: string, target: HTMLTextAreaElement) {
  const { selectionEnd, selectionStart, value } = target

  target.value = value.substring(0, selectionStart) + text + value.substring(selectionEnd)
  target.selectionStart = target.selectionEnd = selectionStart + text.length
}

export default function Editor({ close }: Editor) {
  const history = useHistory()
  const match = useRouteMatch<{ slug: string }>(Archive.route)
  const slug = match?.params?.slug
  const user = React.useContext(UserContext)

  const { data } = usePostQuery({ skip: !match || !user, variables: { slug } })
  const [content, setContent] = React.useState(data?.post?.content)
  const [name, setName] = React.useState(data?.post?.name)
  const [state, setState] = React.useState(data?.post?.state || PostState.Draft)
  const [updateOrCreatePost] = useUpdateOrCreatePostMutation()

  const onSubmit = async(e: React.FormEvent) => {
    e.preventDefault()

    const { data: { updateOrCreatePost: { success, post: { url } } } } = await updateOrCreatePost({
      awaitRefetchQueries: true,
      variables: { input: { id: data?.post?.id, name, content, state } },
      refetchQueries: ({ data: { updateOrCreatePost: { post: { slug: nextSlug } } } }) => (
        ['Home', { query: POST_QUERY, variables: { slug: nextSlug } }]
      ),
    })

    if (success) close(() => history.push(url))
  }

  const margins = [0, 0, '2rem']
  const widths = [1, 1, 1 / 2]

  const onKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key !== 'Tab') return

    e.preventDefault()

    insertAtCaret('  ', e.currentTarget)
  }

  const [createAttachment] = useCreateAttachmentMutation()

  const onDrop = async(e: React.DragEvent<HTMLTextAreaElement>) => {
    if (!user) return

    e.preventDefault()

    const { currentTarget, dataTransfer } = e

    const { data: { createAttachment: { success, url } } } = await createAttachment({
      variables: { input: { file: dataTransfer.items[0].getAsFile() } },
    })

    if (success) insertAtCaret(`![](${url})`, currentTarget)
  }

  const onClick = () => setState(state => Object.values(PostState).filter(value => value !== state)[0])

  return (
    <Layout height="100%">
      <Head
        meta={{
          description: 'Editor',
          title: 'Editor',
          type: '',
          url: window.location.href,
        }}
      />

      <Flex
        flexDirection={['column', 'column', 'row']}
        height="100%"
      >
        <EditorFlex
          as="form"
          flexDirection="column"
          mb={['2rem', '2rem', 0]}
          mr={margins}
          onSubmit={onSubmit}
          width={widths}
        >
          <input
            onChange={e => setName(e.target.value)}
            placeholder={PLACEHOLDER_NAME}
            type="text"
            defaultValue={name}
          />

          <textarea
            onChange={e => setContent(e.target.value)}
            onKeyDown={onKeyDown}
            placeholder={PLACEHOLDER_CONTENT}
            defaultValue={content}
            onDrop={onDrop}
          />

          {user && (
            <Flex>
              <Button
                fontSize="0.7em"
                mr="2rem"
                style={{ textTransform: 'uppercase' }}
                type="button"
                onClick={onClick}
              >
                {state}
              </Button>

              <Button type="submit" flexGrow={1}>
                {data ? 'Update' : 'Create'}
              </Button>
            </Flex>
          )}
        </EditorFlex>

        <Flex
          flexDirection="column"
          ml={margins}
          overflowY="scroll"
          width={widths}
        >
          <Content
            content={content || PLACEHOLDER_CONTENT}
            created="May 06, 1992"
            name={name || PLACEHOLDER_NAME}
            state={state}
          />
        </Flex>
      </Flex>
    </Layout>
  )
}

Editor.modalFull = true
