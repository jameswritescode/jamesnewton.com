import styled from 'styled-components'

import {
  flexbox, FlexboxProps,
  space, SpaceProps,
  typography, TypographyProps,
} from 'styled-system'

const Button = styled.button<FlexboxProps & SpaceProps & TypographyProps>`
  background-color: ${props => props.theme.backgroundColor};
  border-radius: 3px;
  border: 1px solid ${props => props.theme.primary};
  color: ${props => props.theme.primary};
  cursor: pointer;
  font-size: 1em;
  font-weight: bold;
  padding: 1em;

  ${flexbox}
  ${space}
  ${typography}
`

export default Button
