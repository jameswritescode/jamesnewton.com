// NOTE: styled-system's breakpoints are 40em, 52em, 64em (400px, 520px, 640px)

type Theme = {
  backgroundColor: string,
  borderRadius: string,
  primary: string,
  secondary: string,

  mark: {
    backgroundColor: string,
    color: string,
  }
}

const defaults = { borderRadius: '3px' }

const light: Theme = {
  ...defaults,

  backgroundColor: 'white',
  primary: '#191919',
  secondary: '#f7f7f7',
  borderRadius: '3px',

  mark: {
    backgroundColor: '#fff9b2',
    color: '#191919',
  },
}

const dark: Theme = {
  ...defaults,

  backgroundColor: light.primary,
  primary: light.backgroundColor,
  secondary: '#080808',

  mark: {
    backgroundColor: 'yellow',
    color: light.primary,
  },
}

export type StyledProps = {
  theme: Theme,
}

export default {
  dark,
  light,
}
