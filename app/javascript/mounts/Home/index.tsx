import * as React from 'react'
import { Route, Switch } from 'react-router-dom'

import Layout from '~ui/Layout'

import { MODALS, Modal } from './modals'
import Blog from './Blog'
import Main from './Main'
import Resume from './Resume'

const MODAL_DEFAULT = { name: 'Nothing', open: false }

export default function Home() {
  const [input, setInput] = React.useState(null)
  const [{ name, open }, setModal] = React.useState(MODAL_DEFAULT)

  React.useEffect(() => {
    const toggle = ({ key }: KeyboardEvent) => {
      if (['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return

      if (input === 'g' && key === 'e') setModal({ open: true, name: 'Editor' })
      if (input === 'g' && key === 'l') setModal({ open: true, name: 'Login' })
      if (key === '?') setModal({ open: true, name: 'Help' })
      if (key === 'Escape' && open) setModal(MODAL_DEFAULT)

      setInput(key)
    }

    document.addEventListener('keydown', toggle)

    return () => document.removeEventListener('keydown', toggle)
  }, [input, open, setModal])

  const component = MODALS[name]

  return (
    <>
      <Modal
        appElement={document.querySelector('div#mount')}
        isOpen={open}
        onRequestClose={() => setModal(MODAL_DEFAULT)}
        shouldCloseOnOverlayClick
        style={{ overlay: { backgroundColor: 'rgba(255, 255, 255, 0.25)' } }}
        full={component.modalFull}
      >
        {React.createElement(component)}
      </Modal>

      <Layout>
        <Switch>
          <Route path="/blog/:slug">
            <Blog />
          </Route>

          <Route path="/resume">
            <Resume />
          </Route>

          <Route exact path="/">
            <Main />
          </Route>
        </Switch>
      </Layout>
    </>
  )
}
