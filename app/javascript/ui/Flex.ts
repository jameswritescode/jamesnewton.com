import styled from 'styled-components'
import { flexbox, FlexboxProps } from 'styled-system'

const Flex = styled.div<FlexboxProps>`
  display: flex;
  ${flexbox};
`

export default Flex
