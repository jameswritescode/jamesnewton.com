import * as React from 'react'
import * as ReactDOM from 'react-dom'

function Home() {
  return <h1>hello world</h1>
}

document.addEventListener('DOMContentLoaded', () => {
  ReactDOM.render(
    <Home />,
    document.body.appendChild(document.createElement('div')),
  )
})
