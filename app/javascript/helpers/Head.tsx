import * as React from 'react'
import { Helmet } from 'react-helmet'

import { Meta } from '~gql'

type Head = {
  meta: Meta,
  children?: React.ReactNode,
}

export default function Head({ children, meta: { title, description, type } }: Head) {
  return (
    <Helmet>
      <title>{title}</title>
      <meta name="description" content={description} />
      <meta name="title" content={title} />
      <meta property="og:description" content={description} />
      <meta property="og:title" content={title} />
      <meta property="og:type" content={type} />

      {children}
    </Helmet>
  )
}
