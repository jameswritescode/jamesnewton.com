import * as React from 'react'
import * as ReactMarkdown from 'react-markdown'
import * as footnotes from 'remark-footnotes'
import * as gfm from 'remark-gfm'

// import mark from './mark'

const REMARK_PLUGINS = [
  // mark
  footnotes,
  gfm,
]

function Image(props) {
  return <img loading="lazy" {...props} />
}

function Table({ children }) {
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
