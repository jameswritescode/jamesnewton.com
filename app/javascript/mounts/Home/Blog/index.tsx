import * as React from 'react'
import { Switch, Route } from 'react-router-dom'

import Archive from './Archive'
import Post from './Post'

const PATH = '/blog'

export default function Blog() {
  return (
    <>
      <Switch>
        <Route path={Archive.route}>
          <Post />
        </Route>

        <Route path={PATH}>
          <Archive />
        </Route>
      </Switch>
    </>
  )
}

Blog.route = PATH
