import * as React from 'react'
import * as ReactDOM from 'react-dom'

type Props = {
  name: string,
}

const Hello = (props: Props) => (
  <div>Hello {props.name}!</div>
)

Hello.defaultProps = {
  name: 'David',
}

document.addEventListener('DOMContentLoaded', () => {
  ReactDOM.render(
    <Hello name="React" />,
    document.body.appendChild(document.createElement('div')),
  )
})
