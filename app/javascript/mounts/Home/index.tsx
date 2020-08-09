import * as React from 'react'
import { Route, Switch, useHistory } from 'react-router-dom'

import Layout from '~ui/Layout'
import UserContext from '~helpers/user-context'
import { useMeQuery } from '~gql'

import Blog from './Blog'
import Main from './Main'
import Resume from './Resume'
import { MODALS, Modal } from './modals'

const MODAL_DEFAULT = { name: 'Nothing', open: false }

export default function Home() {
  const [lastKey, setLastKey] = React.useState(null)
  const [{ name, open }, setModal] = React.useState(MODAL_DEFAULT)
  const history = useHistory()

  React.useEffect(() => {
    const toggle = ({ key }: KeyboardEvent) => {
      if (['INPUT', 'TEXTAREA'].includes(document.activeElement.tagName)) return

      const g = lastKey === 'g'

      if (g && key === 'e') setModal({ open: true, name: 'Editor' })
      if (g && key === 'l') setModal({ open: true, name: 'Login' })
      if (g && key === 'u') setModal({ open: true, name: 'Upload' })

      if (g && key === 'h') {
        history.push(Main.route)
        setModal(MODAL_DEFAULT)
      }

      if (key === '?') setModal({ open: true, name: 'Help' })

      setLastKey(key)
    }

    document.addEventListener('keydown', toggle)

    return () => document.removeEventListener('keydown', toggle)
  }, [lastKey, open, setModal, history])

  const close = (callback?: () => void) => {
    setModal(MODAL_DEFAULT)

    typeof callback === 'function' && callback()
  }

  const component = MODALS[name]

  const { data } = useMeQuery()

  history.listen(() => {
    window.scrollTo(0, 0)
  })

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
          <Route path={Blog.route}>
            <Blog />
          </Route>

          <Route path={Resume.route}>
            <Resume />
          </Route>

          <Route exact path={Main.route}>
            <Main />
          </Route>
        </Switch>
      </Layout>
    </UserContext.Provider>
  )
}
