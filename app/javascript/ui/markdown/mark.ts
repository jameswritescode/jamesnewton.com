const MARK_SYMBOL = ':'

// reference https://github.com/remarkjs/remark/blob/master/packages/remark-parse/lib/tokenize/strong.js
function markTokenizer(eat: any, value: string) {
  let index = 0
  let character = value.charAt(index)

  if (
    (character !== MARK_SYMBOL && character !== MARK_SYMBOL) ||
    value.charAt(++index) !== character
  ) return

  const marker = character
  const subvalue = marker + marker
  let queue = ''
  let previous = ''
  character = ''

  while (++index < value.length) {
    previous = character
    character = value.charAt(index)

    if (
      character === marker &&
      value.charAt(index + 1) === marker &&
      previous !== ' '
    ) {
      character = value.charAt(index + 2)

      if (character === marker || !queue.trim()) return

      const now = eat.now()
      now.column += 2
      now.offset += 2

      return eat(subvalue + queue + subvalue)({
        type: 'mark',
        children: this.tokenizeInline(queue, now),
      })
    }

    queue += character
  }
}

markTokenizer.locator = (value: string, fromIndex: number) => value.indexOf(MARK_SYMBOL, fromIndex)

export default function mark() {
  const parser = this.Parser.prototype
  const tokenizers = parser.inlineTokenizers
  const methods = parser.inlineMethods

  tokenizers.mark = markTokenizer

  methods.splice(methods.indexOf('text'), 0, 'mark')
}
