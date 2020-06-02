import * as React from 'react'
import * as ReactDOM from 'react-dom'

import styled from 'styled-components'

const Default = styled.div`
  font-size: 2rem;
  line-height: 2;
  padding: 4rem;

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
    border-left: 0.7rem solid black;
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
    color: black;
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

  img {
    border-radius: 3px;
    border: 1px solid #f7f7f7;
    max-height: 70rem;
    max-width: 100%;
    vertical-align: top;
  }

  // TODO: font-weight is broken past ~20px in Chrome for system-ui/Blink
  // this only executes in chrome to make it 1 pixel less to make some bold work
  @media screen and (-webkit-min-device-pixel-ratio: 0) and (min-resolution: .001dpcm) {
    strong, a {
      font-size: 19.999999px;
    }
  }
`

const Writing = styled(Default)`
  background-color: #191919;
  color: white;

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
`

function Hello() {
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
    </Component>
  ))

  return <>{content}</>
}

document.addEventListener('DOMContentLoaded', () => {
  ReactDOM.render(
    <Hello />,
    document.body.appendChild(document.createElement('div')),
  )
})
