import * as React from 'react'
import * as ReactMarkdown from 'react-markdown'
import * as footnotes from 'remark-footnotes'
import * as gfm from 'remark-gfm'
import styled from 'styled-components'

const REMARK_PLUGINS = [
  footnotes,
  gfm,
]

function Image(props) {
  return <img loading="lazy" {...props} />
}

const Badge = styled.code`
  && {
    background-color: ${props => props.theme.primary};
    border-radius: 0 ${props => props.theme.borderRadius};
    color: ${props => props.theme.secondary};
    font-size: 0.55em;
    line-height: initial;
    position: absolute;
    right: 0;
    top: 0;
    user-select: none;
  }
`

function Pre({ children }: { children: React.ReactNode }) {
  const language = children[0].props.className
  const badge = language && language.split('-')[1]

  return (
    <div className="markdown-code">
      {badge && <Badge>{badge}</Badge>}

      <pre>
        {children}
      </pre>
    </div>
  )
}

function Table({ children }: { children: React.ReactNode }) {
  return (
    <div className="markdown-table">
      <table>
        {children}
      </table>
    </div>
  )
}

const RENDERERS = {
  image: Image,
  imageReference: Image,
  pre: Pre,
  table: Table,
}

export default function Markdown({ content }: { content: string }) {
  return (
    <ReactMarkdown
      // eslint-disable-next-line react/no-children-prop
      children={content}
      components={RENDERERS}
      remarkPlugins={REMARK_PLUGINS}
    />
  )
}
