import * as React from 'react'
import styled from 'styled-components'
import { Link } from 'react-router-dom'
import { space, SpaceProps, position, PositionProps } from 'styled-system'

import Flex from '~ui/Flex'

export const Code = styled.code<SpaceProps & PositionProps>`
  font-size: 1.2rem;
  ${space}
  ${position}
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
  children?: React.ReactElement,
  title?: string,
}

export function Header({ children, title, back }: Header) {
  return (
    <Flex
      alignItems="center"
      flexDirection={['column', 'column', 'row']}
      mb="2rem"
    >
      {back && (
        <StyledLink to="/">
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
