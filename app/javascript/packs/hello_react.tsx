import * as React from 'react'
import * as ReactDOM from 'react-dom'

import styled from 'styled-components'

const Red = styled.div`
  color: red;
`

const Hello = () => (
  <>
    <Red>Red!</Red>
  </>
)

document.addEventListener('DOMContentLoaded', () => {
  ReactDOM.render(
    <Hello />,
    document.body.appendChild(document.createElement('div')),
  )
})
