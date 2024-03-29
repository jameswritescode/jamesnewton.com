import * as React from 'react'
import styled, { createGlobalStyle } from 'styled-components'
import { layout, LayoutProps } from 'styled-system'

import { StyledProps } from '~ui/theme'

// SUPPORTED ELEMENTS:
// MD------HTML
//         q
//         table
// ![x](y) img
// # x     h1, h2, hN..
// * x     ol, ul
// ***x*** em + strong
// **x**   strong
// *x*     em
// ---     hr
// >       blockquote
// [x](y)  a
// ```x``` pre
// `x`     code
// ~~x~~   del

const GlobalStyle = createGlobalStyle<StyledProps>`
  :root {
    scrollbar-color: ${props => `${props.theme.primary} transparent`};
    scrollbar-width: thin;
  }

  body, pre, .markdown-table {
    scrollbar-width: thin;

    ::-webkit-scrollbar {
      background-color: transparent;
      width: .7rem;
      height: .7rem;
    }

    ::-webkit-scrollbar-thumb {
      background-color: ${props => props.theme.primary};
      border-radius: 1em;
    }
  }

  body {
    background-color: ${props => props.theme.backgroundColor};
  }

  .ReactModal__Overlay {
    z-index: 9001;
  }
`

const Container = styled.div`
  ${layout}

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
    margin-left: 2rem;

    li {
      p:last-of-type {
        margin-bottom: 0;
      }
    }
  }

  code, pre {
    border-radius: ${props => props.theme.borderRadius};
  }

  code {
    background-color: ${props => props.theme.secondary};
    font-size: 0.8em;
    font-variant-ligatures: normal;
    padding: 4px;
  }

  .markdown-code {
    position: relative;
  }

  pre {
    background-color: ${props => props.theme.secondary};
    line-height: normal;
    overflow-x: auto;
    padding: 2rem;
    width: 100%;

    code {
      padding: 0;
    }
  }

  blockquote {
    border-left: 0.7rem solid ${props => props.theme.primary};
    padding-left: 1rem;
  }

  q {
    quotes: "“" "”";
  }

  p, ol, ul, blockquote, h1, hr, .markdown-table, .markdown-code, .footnotes {
    hyphens: auto;
    margin-bottom: 2rem;

    :last-child {
      margin-bottom: 0;
    }
  }

  .markdown-table {
    overflow-x: auto;
  }

  table {
    border-collapse: collapse;
    white-space: nowrap;
    width: 100%;
  }

  td, th {
    padding: 1rem;
  }

  th {
    border-bottom: 2px solid ${props => props.theme.primary};
    text-align: left;
  }

  td {
    border-bottom: 1px solid ${props => props.theme.primary};
  }

  tr:last-child {
    td {
      border-bottom: 0;
    }
  }

  a {
    font-weight: 600;
    text-decoration: none;

    :after {
      content: "›";
      position: relative;
      top: -1px;
      right: -2px;
    }
  }

  p > img {
    display: block;
    margin: 0 auto;
    max-height: 70rem;
    max-width: 100%;
  }

  textarea, input {
    background-color: ${props => props.theme.backgroundColor};
    color: ${props => props.theme.primary};
  }

  hr {
    color: ${props => props.theme.secondary};
  }

  sup:target {
    a {
      background-color: ${props => props.theme.primary};
      color: ${props => props.theme.secondary};
    }
  }

  a.footnote-ref {
    background-color: ${props => props.theme.secondary};
    border-radius: ${props => props.theme.borderRadius};
    color: ${props => props.theme.primary};
    font-size: .7em;
    margin-left: 2px;
    padding: 0 2px;

    ::after {
      content: '';
    }
  }

  .footnotes {
    font-size: 0.75em;

    a::after {
      content: '';
    }

    li:target {
      ::marker {
        color: ${props => props.theme.primary};
      }

      &, * {
        background-color: ${props => props.theme.primary};
        color: ${props => props.theme.secondary};
      }

      a {
        color: ${props => props.theme.secondary};
      }
    }
  }

  .contains-task-list {
    list-style: none;
  }

  @media (max-width: 52em) {
    font-size: 1.6rem;
    padding: 2rem;
  }
`

type Layout = {
  children: React.ReactNode,
} & LayoutProps

export default function Layout({ children, ...props }: Layout) {
  return (
    <>
      <GlobalStyle />

      <Container {...props}>
        {children}
      </Container>
    </>
  )
}
