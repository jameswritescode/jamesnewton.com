import styled from 'styled-components'
import { space, SpaceProps, position, PositionProps } from 'styled-system'

const Code = styled.code<SpaceProps & PositionProps>`
  font-size: 1.2rem;
  ${space}
  ${position}
`

export default Code
