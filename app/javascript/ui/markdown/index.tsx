import * as React from 'react'
import styled from 'styled-components'
import Markdoc, { nodes, ConfigType, Tag } from '@markdoc/markdoc'

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

function Fence({ children, ...rest }: { children: React.ReactNode, 'data-language': string }) {
  const language = rest['data-language']

  return (
    <div className="markdown-code">
      {language && <Badge>{language}</Badge>}

      <pre>
        <code>
          {children}
        </code>
      </pre>
    </div>
  )
}

function Image(props: { src: string, alt: string }) {
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

const config: ConfigType = {
  nodes: {
    fence: {
      ...nodes.fence,
      render: 'Fence',
      transform(node, config) {
        const base = nodes.fence.transform(node, config) as Tag

        return new Tag('Fence', base.attributes, base.children)
      },
    },
    image: {
      ...nodes.image,
      render: 'Image',
    },
    table: {
      ...nodes.table,
      render: 'Table',
    },
  },
}

const components = {
  Fence,
  Image,
  Table,
}

export default function Markdown({ content }: { content: string }) {
  const ast = Markdoc.parse(content)
  const inner = Markdoc.transform(ast, config)

  return Markdoc.renderers.react(inner, React, { components })
}
