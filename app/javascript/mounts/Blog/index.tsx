import * as React from 'react'
import styled from 'styled-components'

const Default = styled.div`
  font-size: 2rem;
  line-height: 2;
  padding: 4rem;

  * {
    color: #191919;

    ::selection {
      background-color: #191919;
      color: white;
    }
  }

  ul, ol {
    list-style-position: inside;
  }

  pre {
    background-color: #f7f7f7;
    line-height: normal;
    width: 100%;
    padding: 2rem;
    overflow-x: scroll;
  }

  blockquote {
    border-left: 0.7rem solid #191919;
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
    background-color: #f7f7f7;
    padding: 4px;
  }

  pre, code {
    border-radius: 3px;
  }

  // TODO: would be nice to have p text-align: center if img is present
  img {
    border-radius: 3px;
    border: 1px solid #f7f7f7;
    max-height: 70rem;
    max-width: 100%;
    vertical-align: top;
  }

  mark {
    background-color: rgba(255, 249, 178);
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

const Writing = styled(Default)`
  background-color: #191919;

  * {
    color: white;

    ::selection {
      background-color: white;
      color: #191919;
    }
  }

  pre {
    display: none;
  }

  code {
    font-family: inherit;
    background-color: inherit;
    padding: 0;
  }

  a {
    color: white;
  }

  blockquote {
    border-left-color: white;
  }

  img {
    border: 1px solid #080808;
  }

  mark {
    color: #191919;
  }
`

export default function Blog() {
  const layouts = [Default, Writing]

  const content = layouts.map((Component, index) => (
    <Component key={index}>
      <h1>This Looks like an Official Blog Title</h1>

      <p>Lorem ipsum dolor sit amet, <a href="#">consectetur adipiscing elit</a>, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, <a href="#">sunt in culpa</a> qui officia deserunt mollit anim id est laborum.</p>

      <p>
        <img src="http://blog.jamesnewton.com/attachments/1560481065-raw.gif" />
      </p>

      <ul>
        <li>this is a line item</li>
        <li>another line item</li>
        <li>for an unordered list</li>
      </ul>

      <blockquote>
        <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit, <u>sed do</u> eiusmod tempor incididunt ut labore et dolore magna aliqua.</p>
        <q>Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat.</q>
      </blockquote>

      <pre>
        {`#include <stdio.h>

#ifndef __PERSON_H__
#define __PERSON_H__

# this is a random comment to look at on smaller viewports

typedef struct {
  char *first_name;
  char *last_name;
  int  age;
} person_t;

#endif`}
      </pre>

      <p>Lorem ipsum dolor sit amet, <code>consectetur adipiscing elit</code>, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>

      <ol>
        <li>this is a line item</li>
        <li>another line item</li>
        <li>for an ordered list</li>
      </ol>

      <p><strong>Lorem ipsum dolor sit amet,</strong> <i>consectetur</i> <em>adipiscing</em> elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit <a href="#">esse</a> cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>

      <p>
        <img src="http://blog.jamesnewton.com/attachments/1446406349-raw.jpg" />
      </p>

      <p>Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.</p>

      <p>Sed ut perspiciatis unde omnis iste natus error sit voluptatem accusantium doloremque laudantium, totam rem aperiam, eaque ipsa quae ab illo inventore veritatis et <mark>quasi architecto beatae vitae dicta</mark> sunt explicabo. Nemo enim ipsam voluptatem quia voluptas sit aspernatur aut odit aut fugit, sed quia consequuntur magni dolores eos qui ratione voluptatem sequi nesciunt. Neque porro quisquam est, qui dolorem ipsum quia dolor sit amet, consectetur, adipisci velit, sed quia non numquam eius modi tempora incidunt ut labore et dolore magnam aliquam quaerat voluptatem. Ut enim ad minima veniam, quis nostrum exercitationem ullam corporis suscipit laboriosam, nisi ut aliquid ex ea commodi consequatur? Quis autem vel eum iure reprehenderit qui in ea voluptate velit esse quam nihil molestiae consequatur, vel illum qui dolorem eum fugiat quo voluptas nulla pariatur?</p>
    </Component>
  ))

  return <>{content}</>
}
