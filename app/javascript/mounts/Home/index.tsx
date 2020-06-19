import * as React from 'react'
import { BrowserRouter, Route, Switch } from 'react-router-dom'

import Layout from '~ui/Layout'

import Blog from './Blog'
import Editor from './Editor'
import Main from './Main'
import Resume from './Resume'

export default function Home() {
  return (
    <BrowserRouter>
      <Layout>
        <Switch>
          <Route path="/blog/:slug">
            <Blog />
          </Route>

          <Route path="/resume">
            <Resume />
          </Route>

          <Route path="/editor">
            <Editor />
          </Route>

          <Route exact path="/">
            <Main />
          </Route>
        </Switch>
      </Layout>
    </BrowserRouter>
  )
}
