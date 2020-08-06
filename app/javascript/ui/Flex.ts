import styled from 'styled-components'

import {
  flexbox, FlexboxProps,
  layout, LayoutProps,
  space, SpaceProps,
  typography, TypographyProps,
} from 'styled-system'

const Flex = styled.div<FlexboxProps & SpaceProps & LayoutProps & TypographyProps>`
  display: flex;
  ${flexbox}
  ${layout}
  ${space}
  ${typography}
`

export default Flex
