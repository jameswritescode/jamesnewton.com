export type StyledProps = {
  theme: {
    backgroundColor: string,
    primary: string,
    secondary: string,
    mark: {
      backgroundColor: string,
      color: string,
    }
  }
}

export const light: StyledProps['theme'] = {
  backgroundColor: 'white',
  primary: '#191919',
  secondary: '#f7f7f7',

  mark: {
    backgroundColor: '#fff9b2',
    color: '#191919',
  },
}

export const dark: StyledProps['theme'] = {
  backgroundColor: light.primary,
  primary: light.backgroundColor,
  secondary: '#080808',

  mark: {
    backgroundColor: 'yellow',
    color: light.primary,
  },
}
