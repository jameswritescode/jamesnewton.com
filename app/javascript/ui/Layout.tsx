import * as React from 'react'
import styled, { createGlobalStyle } from 'styled-components'

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
// ---     hr
// ::x::   mark
// >       blockquote
// [x](y)  a
// ```x``` pre
// `x`     code

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

  p, ol, ul, pre, blockquote, h1, table, hr {
    margin-bottom: 2rem;
    max-width: 1100px;

    :last-child {
      margin-bottom: 0;
    }
  }

  table {
    border-collapse: collapse;
  }

  table, td, th {
    border: 1px solid ${props => props.theme.primary};
  }

  th {
    border-bottom: 2px solid ${props => props.theme.primary};
    text-align: left;
  }

  td, th {
    padding: 1rem;
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
  return (
    <>
      <GlobalStyle />

      <Container>
        {children}
      </Container>
    </>
  )
}
