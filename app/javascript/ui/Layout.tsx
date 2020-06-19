import * as React from 'react'
import styled, { createGlobalStyle } from 'styled-components'
import { useHistory, useLocation } from 'react-router-dom'

import { StyledProps } from '~ui/theme'

// SUPPORTED ELEMENTS:
// MD ---- HTML
//         q
// ![x](y) img
// # x     h1, h2, hn..
// * x     ol, ul
// ***x*** em + strong
// **x**   strong
// *x*     em
// ::      mark
// >       blockquote
// []()    a
// `       code
// ```     pre

// TODO: How should this be typed?
const GlobalStyle = createGlobalStyle<StyledProps>`
  body {
    background-color: ${props => props.theme.backgroundColor};
  }
`

const Container = styled.div`
  font-size: 2rem;
  line-height: 2;
  padding: 4rem;

  * {
    color: ${props => props.theme.primary};

    ::selection {
      background-color: ${props => props.theme.primary};
      color: ${props => props.theme.backgroundColor};
    }
  }

  ul, ol {
    list-style-position: inside;
  }

  pre {
    background-color: ${props => props.theme.secondary};
    line-height: normal;
    width: 100%;
    padding: 2rem;
    overflow-x: scroll;
  }

  blockquote {
    border-left: 0.7rem solid ${props => props.theme.primary};
    padding-left: 1rem;
  }

  q {
    quotes: "“" "”";
  }

  p, ol, ul, pre, blockquote, h1 {
    margin-bottom: 2rem;
    max-width: 1100px;

    :last-child {
      margin-bottom: 0;
    }
  }

  a {
    font-weight: bold;
    text-decoration: none;

    :after {
      content: " »";
    }
  }

  code {
    background-color: ${props => props.theme.secondary};
    padding: 4px;
  }

  pre, code {
    border-radius: 3px;
  }

  // TODO: would be nice to have p text-align: center if img is present
  p > img {
    border-radius: 3px;
    border: 1px solid ${props => props.theme.secondary};
    max-height: 70rem;
    max-width: 100%;
    vertical-align: top;
  }

  mark {
    background-color: ${props => props.theme.mark.backgroundColor};
    color: ${props => props.theme.mark.color}
  }

  li ul, li ol {
    padding-left: 4rem;
  }

  @media (max-width: 52em) {
    font-size: 1.6rem;
    padding: 2rem;
  }
`

type Layout = {
  children: React.ReactNode,
}

export default function Layout({ children }: Layout) {
  const history = useHistory()
  const [input, setInput] = React.useState(null)
  const { pathname } = useLocation()

  React.useEffect(() => {
    const toggle = ({ keyCode }: KeyboardEvent) => {
      // ge
      if (input === 71 && keyCode === 69 && !['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) {
        pathname === '/editor' ? history.goBack() : history.push('/editor')
      }

      setInput(keyCode)
    }

    document.addEventListener('keydown', toggle)

    return () => document.removeEventListener('keydown', toggle)
  }, [history, pathname, input])

  return (
    <>
      <GlobalStyle />

      <Container>
        {children}
      </Container>
    </>
  )
}
