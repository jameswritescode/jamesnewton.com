import * as React from 'react'
import { BrowserRouter, Route, Switch } from 'react-router-dom'

import Layout from '~ui/Layout'

import Blog from './Blog'
import Main from './Main'

export default function Home() {
  return (
    <Layout>
      <BrowserRouter>
        <Switch>
          <Route path="/blog/:slug">
            <Blog />
          </Route>

          <Route exact path="/">
            <Main />
          </Route>
        </Switch>
      </BrowserRouter>
    </Layout>
  )
}
