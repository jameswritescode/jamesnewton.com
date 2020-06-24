import styled from 'styled-components'

const Button = styled.button`
  background-color: ${props => props.theme.backgroundColor};
  border-radius: 3px;
  border: 1px solid ${props => props.theme.primary};
  color: ${props => props.theme.primary};
  font-size: 1em;
  font-weight: bold;
  padding: 1em;
`

export default Button
