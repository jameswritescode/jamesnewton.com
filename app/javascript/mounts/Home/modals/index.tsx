import * as React from 'react'
import * as ReactModal from 'react-modal'
import styled from 'styled-components'

import Layout from '~ui/Layout'
import UserContext from '~helpers/user-context'

import Editor from './Editor'
import Login from './Login'
import Upload from './Upload'

function Help() {
  const user = React.useContext(UserContext)

  return (
    <Layout>
      <p><code>?</code>  open this dialog</p>
      <p><code>ge</code> open editor</p>
      <p><code>gh</code> go home</p>
      <p><code>gl</code> open login</p>
      {user && <p><code>gu</code> open uploads</p>}
    </Layout>
  )
}

Help.modalFull = false

function Nothing() {
  return <span />
}

export const MODALS = {
  Editor,
  Help,
  Login,
  Nothing,
  Upload,
}

export const Modal = styled<any>(ReactModal)`
  background-color: ${props => props.theme.backgroundColor};
  border-radius: 3px;
  border: 1px solid ${props => props.theme.primary};
  outline: none;
  overflow: auto;
  padding: 0;
  position: absolute;

  ${props => (
    props.full ? `
      bottom: 4rem;
      left: 4rem;
      right: 4rem;
      top: 4rem;
    ` : `
      bottom: auto;
      left: 50%;
      right: auto;
      top: 50%;
      transform: translate(-50%, -50%);
    `
  )}

  @media (max-width: 52em) {
    border-radius: 0;
    bottom: 0;
    left: 0;
    position: fixed;
    right: 0;
    top: 0;
    transform: initial;
  }
`
