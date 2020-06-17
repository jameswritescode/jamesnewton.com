import * as React from 'react'
import styled, { createGlobalStyle } from 'styled-components'

// SUPPORTED ELEMENTS:
// MD ---- HTML
//         mark
//         q
// ![x](y) img
// # x     h1, h2, hn..
// * x     ol, ul
// **x**   strong
// *x*     em
// >       blockquote
// []()    a
// `       code
// ```     pre

// TODO: How should this be typed?
const GlobalStyle = createGlobalStyle<any>`
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

  // TODO: font-weight is broken past ~20px in Chrome for system-ui/Blink
  // this only executes in chrome to make it 1 pixel less to make some bold work
  // https://bugs.chromium.org/p/chromium/issues/detail?id=1057654
  @media screen and (-webkit-min-device-pixel-ratio: 0) and (min-resolution: .001dpcm) {
    strong, a {
      font-size: 19.999999px;
    }
  }

  @media (max-width: 52em) {
    font-size: 1.6rem;
    padding: 2rem;

    strong, a {
      font-size: 1.6rem;
    }
  }
`

type Layout = {
  children: React.ReactNode,
}

export default function Layout({ children }: Layout) {
  return (
    <>
      <GlobalStyle />

      <Container>
        {children}
      </Container>
    </>
  )
}
