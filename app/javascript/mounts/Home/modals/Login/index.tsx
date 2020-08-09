import * as React from 'react'
import styled from 'styled-components'

import Button from '~ui/Button'
import UserContext from '~helpers/user-context'
import { useLoginMutation, useLogoutMutation } from '~gql'

const LoginLayout = styled.form`
  background-color: #ff5f60;
  color: #42494e;
  display: flex;
  flex-direction: column;
  padding: 10rem;

  h1 {
    font-size: 2.5rem;
    font-weight: 500;
    letter-spacing: 0.5rem;
    margin-bottom: 1rem;
    text-align: center;
    text-transform: uppercase;

    :last-child {
      margin-bottom: 0;
    }
  }

  input {
    border: none;
    font-size: 1.1rem;
    font-weight: 600;
    outline: none;
    padding: 1.5rem 1.3rem;

    :invalid {
      border-left: 5px solid #ff4e4f;
    }

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
    height: 100%;
  }
`

export default function Login() {
  const [input, setInput] = React.useState({ email: '', password: '' })
  const refetchQueries = ['Me', 'Home', 'Posts']
  const [login] = useLoginMutation({ refetchQueries })
  const [logout] = useLogoutMutation({ refetchQueries })
  const user = React.useContext(UserContext)

  const onChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.currentTarget

    setInput(previous => ({ ...previous, [name]: value }))
  }

  const onSubmit = async(e: React.FormEvent<HTMLFormElement>) => {
    e.preventDefault()

    login({ variables: { input } })
  }

  const onClick = () => logout({ variables: { input: {} } })

  return (
    <LoginLayout onSubmit={onSubmit}>
      <h1>James Newton</h1>

      {user ? (
        <Button onClick={onClick}>
          Logout
        </Button>
      ) : (
        <>
          <input
            name="email"
            onChange={onChange}
            placeholder="email address"
            required
            type="email"
          />

          <input
            autoComplete="off"
            name="password"
            onChange={onChange}
            placeholder="password"
            required
            type="password"
          />

          <input
            type="submit"
            value="Sign in"
          />
        </>
      )}
    </LoginLayout>
  )
}

Login.modalFull = false
