// NOTE: styled-system's breakpoints are 40em, 52em, 64em (400px, 520px, 640px)

export interface Theme {
  backgroundColor: string
  borderRadius: string
  primary: string
  secondary: string
}

const defaults = { borderRadius: '3px' }

const light: Theme = {
  ...defaults,

  backgroundColor: 'white',
  primary: '#191919',
  secondary: '#f7f7f7',
}

const dark: Theme = {
  ...defaults,

  backgroundColor: light.primary,
  primary: light.secondary,
  secondary: '#080808',
}

export type StyledProps = {
  theme: Theme,
}

export default {
  dark,
  light,
}
