import * as React from 'react'

import mark from './mark'

export const PLUGINS = [mark]

type CodeBlock = {
  value: string,
}

function CodeBlock({ value, ...props }: CodeBlock) {
  return <pre {...props}>{value}</pre>
}

type Heading = {
  children: React.ReactNode,
  depth?: number,
  level?: number,
}

// TODO: ReactMarkdown expects a level, but remark returns a depth?
function Heading({ children, depth, level, ...props }: Heading) {
  return React.createElement(`h${depth || level}`, props, children)
}

type Image = {
  alt?: string,
  src: string,
}

function Image(props: Image) {
  return <img loading="lazy" {...props} />
}

type InlineCode = {
  children: React.ReactNode,
}

function InlineCode({ children }: InlineCode) {
  return <code>{children}</code>
}

type Link = {
  children: React.ReactNode,
  href?: string,
  url?: string,
}

// TODO: ReactMarkdown expects a href, but remark returns a url?
function Link({ href, url, children, ...props }: Link) {
  return (
    <a
      href={url || href}
      {...props}
    >
      {children}
    </a>
  )
}

export const RENDERERS: any = {
  code: CodeBlock,
  heading: Heading,
  image: Image,
  imageReference: Image,
  inlineCode: InlineCode,
  link: Link,
  linkReference: Link,
  mark: 'mark',
}
