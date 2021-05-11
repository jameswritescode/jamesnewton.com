import styled, { css } from 'styled-components'

import {
  flexbox, FlexboxProps,
  grid, GridProps,
  layout, LayoutProps,
  space, SpaceProps,
  typography, TypographyProps,
} from 'styled-system'

type SharedProps = SpaceProps & LayoutProps & TypographyProps

const shared = css`
  ${layout}
  ${space}
  ${typography}
`

export const Flex = styled.div<FlexboxProps & SharedProps>`
  display: flex;
  ${flexbox}
  ${shared}
`

export const Block = styled.div<FlexboxProps & GridProps & SharedProps>`
  ${flexbox}
  ${grid}
  ${shared}
`
