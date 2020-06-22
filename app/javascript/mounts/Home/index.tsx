import * as React from 'react'
import { Route, Switch } from 'react-router-dom'

import Layout from '~ui/Layout'
import UserContext from '~helpers/user-context'
import { useMeQuery } from '~gql'

import Blog from './Blog'
import Main from './Main'
import Resume from './Resume'
import { MODALS, Modal } from './modals'

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

  const close = () => setModal(MODAL_DEFAULT)
  const component = MODALS[name]

  const { data } = useMeQuery()

  return (
    <UserContext.Provider value={data?.me}>
      <Modal
        appElement={document.querySelector('div#mount')}
        full={component.modalFull}
        isOpen={open}
        onRequestClose={close}
        shouldCloseOnOverlayClick
        style={{ overlay: { backgroundColor: 'rgba(255, 255, 255, 0.25)' } }}
      >
        {React.createElement(component, { close })}
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
    </UserContext.Provider>
  )
}
