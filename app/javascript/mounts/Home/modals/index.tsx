import * as React from 'react'
import * as ReactModal from 'react-modal'
import styled from 'styled-components'

import Layout from '~ui/Layout'

import Editor from './Editor'

function Help() {
  return (
    <Layout>
      <p><code>?</code>  open this dialog</p>
      <p><code>ge</code> open editor</p>
      <p><code>gl</code> open login</p>
    </Layout>
  )
}

Help.modalFull = false

function Nothing() {
  return <span />
}

const LoginLayout = styled.div`
  background-color: #ff5f60;
  color: #42494e;
  height: 100%;
  padding: 10rem;

  h1 {
    font-size: 2.5rem;
    font-weight: 500;
    letter-spacing: 0.5rem;
    margin-bottom: 1rem;
    text-align: center;
    text-transform: uppercase;
  }

  input {
    border: none;
    display: block;
    font-size: 1.1rem;
    font-weight: 600;
    margin-top: -1px;
    outline: none;
    padding: 1.5rem 1.3rem;
    width: 100%;

    &[type="submit"] {
      background-color: #42494e;
      color: white;
      font-weight: 300;

      &:active {
        background-color: #3a4045;
      }
    }
  }

  @media (max-width: 52em) {
    padding: 5rem;
  }
`

function Login() {
  return (
    <LoginLayout>
      <form>
        <h1>James Newton</h1>

        <input
          placeholder="email address"
          type="email"
        />

        <input
          autoComplete="off"
          placeholder="password"
          type="password"
        />

        <input
          type="submit"
          value="Sign in"
        />
      </form>
    </LoginLayout>
  )
}

Login.modalFull = false

export const MODALS = { Editor, Help, Nothing, Login }

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
