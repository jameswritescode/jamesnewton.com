import * as React from 'react'
import styled from 'styled-components'

import UserContext from '~helpers/user-context'

import {
  namedOperations,
  useAttachmentsQuery,
  useCreateAttachmentMutation,
} from '~gql'

const Div = styled.div`
  min-height: 50px;
  min-width: 50px;

  a, img {
    vertical-align: top;
  }

  img {
    background-color: ${props => props.theme.backgroundColor};
  }

  a {
    align-items: center;
    background-color: ${props => props.theme.primary};
    color: ${props => props.theme.backgroundColor};
    display: inline-flex;
    font-size: 1rem;
    font-weight: bold;
    height: 50px;
    min-width: 50px;
    text-decoration: none;
    text-transform: uppercase;

    span {
      text-align: center;
      width: 100%;
    }
  }
`

export default function Upload() {
  const [mutate] = useCreateAttachmentMutation()
  const user = React.useContext(UserContext)
  const { data } = useAttachmentsQuery()

  if (!data || !user) return <span />

  const onDrop = (e: React.DragEvent<HTMLDivElement>) => {
    e.preventDefault()

    mutate({
      refetchQueries: [namedOperations.Query.Attachments],
      variables: { input: { file: e.dataTransfer.items[0].getAsFile() } },
    })
  }

  return (
    <Div
      onDragOver={e => e.preventDefault()}
      onDrop={onDrop}
    >
      {data.attachments.map(({ url, id, embed, extension, filename }) => (
        <a
          href={url}
          key={id}
          rel="noreferrer"
          target="_blank"
        >
          {!embed ? <span>{extension}</span> : (
            <img
              alt={filename}
              height="50"
              loading="lazy"
              src={url}
              width="50"
            />
          )}
        </a>
      ))}
    </Div>
  )
}
