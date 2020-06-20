import * as React from 'react'
import * as ReactModal from 'react-modal'
import { Route, Switch } from 'react-router-dom'

import Layout from '~ui/Layout'

import Blog from './Blog'
import Editor from './Editor'
import Main from './Main'
import Resume from './Resume'

const MODAL_STYLES = {

  overlay: {
    backgroundColor: 'rgba(255, 255, 255, 0.25)',
  },
}

function Help() {
  return (
    <>
      <p><code>?</code> open this dialog</p>
      <p><code>ge</code> open editor</p>
    </>
  )
}

Help.modalStyles = {
  content: {
    bottom: 'auto',
    left: '50%',
    marginRight: '-50%',
    padding: 0,
    right: 'auto',
    top: '50%',
    transform: 'translate(-50%, -50%)',
  },
}

function Nothing() {
  return <span />
}

const MODALS = {
  editor: Editor,
  help: Help,
  nothing: Nothing,
}

const MODAL_DEFAULT = { name: 'nothing', open: false }

export default function Home() {
  const [input, setInput] = React.useState(null)
  const [{ name, open }, setModal] = React.useState(MODAL_DEFAULT)

  React.useEffect(() => {
    const toggle = ({ key }: KeyboardEvent) => {
      if (['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return

      if (input === 'g' && key === 'e') setModal({ open: true, name: 'editor' })
      if (key === '?') setModal({ open: true, name: 'help' })
      if (key === 'Escape' && open) setModal(MODAL_DEFAULT)

      setInput(key)
    }

    document.addEventListener('keydown', toggle)

    return () => document.removeEventListener('keydown', toggle)
  }, [input, open, setModal])

  const element = MODALS[name]

  return (
    <>
      <ReactModal
        appElement={document.querySelector('div#mount')}
        isOpen={open}
        onRequestClose={() => setModal(MODAL_DEFAULT)}
        shouldCloseOnOverlayClick
        style={{ ...MODAL_STYLES, ...element.modalStyles }}
      >
        <Layout>
          {React.createElement(element)}
        </Layout>
      </ReactModal>

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
