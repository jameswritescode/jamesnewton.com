type Theme = {
  backgroundColor: string,
  primary: string,
  secondary: string,
  mark: {
    backgroundColor: string,
    color: string,
  }
}

const light: Theme = {
  backgroundColor: 'white',
  primary: '#191919',
  secondary: '#f7f7f7',

  mark: {
    backgroundColor: '#fff9b2',
    color: '#191919',
  },
}

const dark: Theme = {
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
