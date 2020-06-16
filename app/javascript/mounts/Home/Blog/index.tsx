import * as Markdown from 'react-markdown'
import * as React from 'react'
import { useLocation } from 'react-router-dom'

/* import { light, dark } from '~ui/theme' */
import Flex from '~ui/Flex'
import Head from '~helpers/Head'
import Layout from '~ui/Layout'
import { usePostQuery } from '~gql'

import Code from '../Code'

function CodeBlock({ value }: { value: string }) {
  return <pre>{value}</pre>
}

function Image(props: any) {
  return <img loading="lazy" {...props} />
}

export default function Blog() {
  const { pathname } = useLocation()
  const parts = pathname.split('/')
  const slug = parts[parts.length - 1]

  const { data } = usePostQuery({ variables: { slug } })

  if (!data) return null

  const { name, content, created, meta } = data.post

  /* const content = [light, dark].map((theme, index) => ( */
  /*   <Layout key={index} theme={theme}> */
  /*     <h1>This Looks like an Official Blog Title</h1> */

  /*     <p>Lorem ipsum dolor sit amet, <a href="#">consectetur adipiscing elit</a>, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, <a href="#">sunt in culpa</a> qui officia deserunt mollit anim id est laborum.</p> */

  /*     <p> */
  /*       <img src="http://blog.jamesnewton.com/attachments/1560481065-raw.gif" /> */
  /*     </p> */

  /*     <ul> */
  /*       <li>this is a line item</li> */
  /*       <li>another line item</li> */
  /*       <li>for an unordered list</li> */
  /*     </ul> */

  /*     <blockquote> */
  /*       <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit, <u>sed do</u> eiusmod tempor incididunt ut labore et dolore magna aliqua.</p> */
  /*       <q>Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</q> */
  /*     </blockquote> */

  /*     <pre> */
  /*       {`#include <stdio.h> */

/* #ifndef __PERSON_H__ */
/* #define __PERSON_H__ */

/* # this is a random comment to look at on smaller viewports */

/* typedef struct { */
  /* char *first_name; */
  /* char *last_name; */
  /* int  age; */
/* } person_t; */

/* #endif`} */
  /*     </pre> */

  /*     <p>Lorem ipsum dolor sit amet, <code>consectetur adipiscing elit</code>, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p> */

  /*     <ol> */
  /*       <li>this is a line item</li> */
  /*       <li>another line item</li> */
  /*       <li>for an ordered list</li> */
  /*     </ol> */

  /*     <p><strong>Lorem ipsum dolor sit amet,</strong> <i>consectetur</i> <em>adipiscing</em> elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit <a href="#">esse</a> cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p> */

  /*     <p> */
  /*       <img src="http://blog.jamesnewton.com/attachments/1446406349-raw.jpg" /> */
  /*     </p> */

  /*     <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p> */

  /*     <p>Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et <mark>quasi architecto beatae vitae dicta</mark> sunt explicabo. Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla pariatur?</p> */
  /*   </Layout> */
  /* )) */

  const renderers = {
    code: CodeBlock,
    image: Image,
    imageReference: Image,
  }

  return (
    <Layout>
      <Head meta={meta} />

      <Flex
        alignItems="center"
        flexDirection={['column', 'column', 'initial']}
      >
        <h1>{name}</h1>

        <Code
          ml="1rem"
          position="relative"
          top="-7px"
        >
          {created}
        </Code>
      </Flex>

      <Markdown
        source={content}
        renderers={renderers}
      />
    </Layout>
  )
}
