import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'
import { useApolloClient } from '@apollo/client'

import Flex from '~ui/Flex'
import UserContext from '~helpers/user-context'
import { useDestroyPostMutation } from '~gql'

import * as POST_QUERY from './Blog/Post/Post.graphql'
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
    refetchQueries: ['Posts', 'Home'],
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
        onMouseOver={() => client.query({ query: POST_QUERY, variables: { slug } })}
        to={url}
      >
        {name}
      </PostLink>
    </StyledFlex>
  )
}
