import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'
import { useApolloClient } from '@apollo/client'

import UserContext from '~helpers/user-context'
import { Flex } from '~ui/Elements'
import { useDestroyPostMutation, namedOperations, PostDocument } from '~gql'

import { Code } from './styles'

const StyledFlex = styled(Flex)`
  white-space: nowrap;
`

const PostLink = styled(Link)`
  overflow-x: hidden;
  text-overflow: ellipsis;
`

const StyledCode = styled(Code)`
  margin-right: 1rem;
  white-space: nowrap;
`

const StyledButton = styled.button`
  background-color: transparent;
  border: none;
  cursor: pointer;
  margin-right: 1rem;
`

export default function PostLine({ created, url, name, slug, state }: any) {
  const client = useApolloClient()
  const user = React.useContext(UserContext)

  const [mutate] = useDestroyPostMutation({
    refetchQueries: [namedOperations.Query.Posts, namedOperations.Query.Home],
    variables: { input: { slug } },
  })

  return (
    <StyledFlex alignItems="center">
      {user && (
        <StyledButton onClick={() => mutate()}>
          ✖
        </StyledButton>
      )}

      {user && state && (
        <StyledCode fontWeight="bold">
          {state}
        </StyledCode>
      )}

      <StyledCode>
        {created}
      </StyledCode>

      <PostLink
        onMouseOver={() => client.query({ query: PostDocument, variables: { slug } })}
        to={url}
      >
        {name}
      </PostLink>
    </StyledFlex>
  )
}
