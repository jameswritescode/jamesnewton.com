import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'
import { useApolloClient } from '@apollo/client'

import {
  position, PositionProps,
  space, SpaceProps,
  typography, TypographyProps,
} from 'styled-system'

import Flex from '~ui/Flex'

import * as HOME_QUERY from './Main/Home.graphql'

export const Code = styled.code<SpaceProps & PositionProps & TypographyProps>`
  font-size: 1.2rem;
  ${position}
  ${space}
  ${typography}
`

const StyledLink = styled(Link)`
  && {
    font-size: 1.2rem;
    margin-right: 2rem;
    text-transform: uppercase;

    :before {
      content: '« ';
      position: relative;
      top: -1px;
    }

    :after {
      content: '';
    }

    @media (max-width: 52em) {
      margin-right: 0;
    }
  }
`

const StyledHeader = styled.h1`
  && {
    margin-bottom: 0;

    @media (max-width: 52em) {
      line-height: 1.5;
      margin-bottom: 1rem;
      text-align: center;
    }
  }
`
type Header = {
  back?: boolean,
  children?: React.ReactNode,
  title?: string,
}

export function Header({ children, title, back }: Header) {
  const client = useApolloClient()

  return (
    <Flex
      alignItems="center"
      flexDirection={['column', 'column', 'row']}
      mb="2rem"
    >
      {back && (
        <StyledLink
          onMouseOver={() => client.query({ query: HOME_QUERY })}
          to="/"
        >
          Home
        </StyledLink>
      )}

      <StyledHeader>
        {title}
      </StyledHeader>

      {children}
    </Flex>
  )
}

Header.defaultProps = {
  back: false,
  title: 'James Newton',
}
