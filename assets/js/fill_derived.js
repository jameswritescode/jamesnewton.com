// No input event is dispatched: the server already holds the refilled value,
// and the next form change submits it back unchanged.
const blank = el => el.value.trim() === ""

export function fillDerived({id, value}, doc = document) {
  const el = doc.getElementById(id)
  if (!el || !blank(el)) return

  if (doc.activeElement !== el) {
    el.value = value
    return
  }

  el.addEventListener("blur", () => { if (blank(el)) el.value = value }, {once: true})
}

export function installFillDerived(target = window) {
  target.addEventListener("phx:fill_derived", e => fillDerived(e.detail))
}
