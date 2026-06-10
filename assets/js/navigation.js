// After a Swup page swap, move keyboard focus into the new content (so users
// don't restart tabbing from the top of the document) and announce the new page
// title to screen readers via the persistent #route-announcer live region.
// Swup is same-document navigation, so without this neither keyboard nor screen
// reader users are told the page changed.
export function focusAfterNavigation(doc = document, win = window) {
  const target = win.location.hash ? doc.querySelector(win.location.hash) : null
  const focusEl = target || doc.getElementById("main")

  if (focusEl) {
    focusEl.setAttribute("tabindex", "-1")
    focusEl.focus()
  }

  const announcer = doc.getElementById("route-announcer")
  if (announcer) announcer.textContent = (doc.title || "").trim()
}
