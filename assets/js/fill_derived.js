// No input event is dispatched: the server already holds the refilled value,
// and the next form change submits it back unchanged.
const blank = el => el.value.trim() === ""
const pendingOnBlur = new WeakMap()

function fillOnBlur(el, value) {
  const waiting = pendingOnBlur.has(el)
  pendingOnBlur.set(el, value)
  if (waiting) return

  el.addEventListener("blur", () => {
    const latest = pendingOnBlur.get(el)
    pendingOnBlur.delete(el)
    if (blank(el)) el.value = latest
  }, {once: true})
}

export function fillDerived({id, value}, doc = document) {
  const el = doc.getElementById(id)
  if (!el || !blank(el)) return

  if (doc.activeElement !== el) {
    el.value = value
    return
  }

  fillOnBlur(el, value)
}

export function installFillDerived(target = window) {
  target.addEventListener("phx:fill_derived", e => fillDerived(e.detail))
}
