import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'
import { useApolloClient } from '@apollo/client'

import {
  position, PositionProps,
  space, SpaceProps,
  typography, TypographyProps,
} from 'styled-system'

import { Block } from '~ui/Elements'
import { HomeDocument } from '~gql'

export const Code = styled.code<SpaceProps & PositionProps & TypographyProps>`
  && {
    font-size: 1.2rem;
  }

  ${position}
  ${space}
  ${typography}
`

export const Container = styled.div<{ centered?: boolean }>`
  ${props => props.centered && 'margin: 0 auto;'}

  max-width: 100rem;
`

const StyledLink = styled(Link)`
  && {
    font-size: 1.2rem;
    text-transform: uppercase;

    :before {
      content: '‹';
      position: relative;
      top: -1px;
      left: -2px;
    }

    :after {
      content: '';
    }
  }
`

const StyledHeader = styled.h1`
  && {
    margin-bottom: 0;
    max-width: unset;

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
  const gridTemplateColumns = [back && '7rem', 'auto', 'max-content'].filter(Boolean).join(' ')

  return (
    <Block
      alignItems="center"
      display={['flex', 'flex', 'grid']}
      flexDirection="column"
      gridAutoFlow="column"
      gridTemplateColumns={gridTemplateColumns}
      mb="2rem"
    >
      {back && (
        <StyledLink
          onMouseOver={() => client.query({ query: HomeDocument })}
          to="/"
        >
          Home
        </StyledLink>
      )}

      <StyledHeader>
        {title}
      </StyledHeader>

      {children}
    </Block>
  )
}

Header.defaultProps = {
  back: false,
  title: 'James Newton',
}
