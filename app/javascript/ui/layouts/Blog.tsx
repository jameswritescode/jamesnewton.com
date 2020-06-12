import styled from 'styled-components'

const Layout = styled.div`
  background-color: ${props => props.theme.backgroundColor};
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
  img {
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

  // TODO: font-weight is broken past ~20px in Chrome for system-ui/Blink
  // this only executes in chrome to make it 1 pixel less to make some bold work
  // https://bugs.chromium.org/p/chromium/issues/detail?id=1057654
  @media screen and (-webkit-min-device-pixel-ratio: 0) and (min-resolution: .001dpcm) {
    strong, a {
      font-size: 19.999999px;
    }
  }
`

export default Layout
