// Drives the /links readout panel from the hovered/focused menu item.
// Pure-DOM, no dependencies. Safe to call on any page (no-ops off /links).

export function readoutFor(el) {
  return {name: el.dataset.name, url: el.dataset.url, desc: el.dataset.desc}
}

export function initLinks() {
  const root = document.querySelector("main.links")
  if (!root) return

  const out = {
    name: root.querySelector('[data-readout="name"]'),
    url: root.querySelector('[data-readout="url"]'),
    desc: root.querySelector('[data-readout="desc"]'),
  }
  if (!out.name || !out.url || !out.desc) return

  // Bind once per element, in case initLinks runs again on the same DOM.
  if (root.dataset.linksInit) return
  root.dataset.linksInit = "1"

  root.querySelectorAll(".links-item").forEach((item) => {
    const update = () => {
      const r = readoutFor(item)
      out.name.textContent = r.name
      out.url.textContent = r.url
      out.desc.textContent = r.desc
    }
    item.addEventListener("mouseenter", update)
    item.addEventListener("focus", update)
  })
}
