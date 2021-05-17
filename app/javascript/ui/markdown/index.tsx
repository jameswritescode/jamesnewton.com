import * as React from 'react'
import * as ReactMarkdown from 'react-markdown'
import * as footnotes from 'remark-footnotes'
import * as gfm from 'remark-gfm'
import styled from 'styled-components'

const REMARK_PLUGINS = [
  footnotes,
  gfm,
]

const Badge = styled.div`
  background-color: ${props => props.theme.primary};
  border-radius: ${props => props.theme.borderRadius};
  color: ${props => props.theme.secondary};
  font-size: 0.7em;
  padding: 0.5em;
  position: absolute;
  right: 2rem;
  user-select: none;
`

interface ICode {
  children: React.ReactNode
  className?: string
  inline?: boolean
}

function Code({ inline, className, children }: ICode) {
  return (
    <code className={className}>
      {!inline && className && <Badge>{className.split('-')[1]}</Badge>}
      {children}
    </code>
  )
}

function Image(props) {
  return <img loading="lazy" {...props} />
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
  code: Code,
  image: Image,
  imageReference: Image,
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
