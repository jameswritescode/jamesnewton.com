import {describe, it, expect, vi, afterEach} from "vitest"
import {SortableGrid} from "./sortable_grid"

function tile(id) {
  const el = document.createElement("div")
  el.dataset.id = id
  return el
}

function mount(grid) {
  const pushEvent = vi.fn()
  const hook = {el: grid, pushEvent}
  Object.setPrototypeOf(hook, SortableGrid)
  hook.mounted()
  return {hook, pushEvent}
}

function fire(el, type) {
  const e = new Event(type, {bubbles: true})
  e.dataTransfer = {}
  e.preventDefault = () => {}
  el.dispatchEvent(e)
  return e
}

afterEach(() => {
  vi.useRealTimers()
  document.body.innerHTML = ""
})

describe("SortableGrid", () => {
  it("pushes the current child id order on drop", () => {
    const grid = document.createElement("div")
    grid.append(tile("1"), tile("2"), tile("3"))
    const {pushEvent} = mount(grid)

    fire(grid, "drop")

    expect(pushEvent).toHaveBeenCalledWith("reorder", {ids: ["1", "2", "3"]})
  })

  it("reorders as soon as the cursor enters a neighbour (no half-way threshold)", () => {
    const grid = document.createElement("div")
    const [a, b, c] = [tile("1"), tile("2"), tile("3")]
    grid.append(a, b, c)
    document.body.append(grid)
    const {pushEvent} = mount(grid)

    fire(a, "dragstart")
    fire(c, "dragover") // drag tile 1 onto tile 3, moving forward
    fire(grid, "drop")

    // Tile 1 lands in tile 3's slot the moment the cursor is over it.
    expect(pushEvent).toHaveBeenCalledWith("reorder", {ids: ["2", "3", "1"]})
  })

  it("marks the grabbed tile as dragging only after the drag image is captured", () => {
    vi.useFakeTimers()
    const grid = document.createElement("div")
    const grabbed = tile("1")
    grid.append(grabbed, tile("2"))
    document.body.append(grid)
    mount(grid)

    fire(grabbed, "dragstart")

    // Still un-dimmed: the browser needs a full-opacity drag image first.
    expect(grabbed.classList.contains("is-dragging")).toBe(false)
    vi.runAllTimers()
    expect(grabbed.classList.contains("is-dragging")).toBe(true)
  })

  it("clears the dragging state on dragend", () => {
    vi.useFakeTimers()
    const grid = document.createElement("div")
    const grabbed = tile("1")
    grid.append(grabbed, tile("2"))
    document.body.append(grid)
    mount(grid)

    fire(grabbed, "dragstart")
    vi.runAllTimers()
    expect(grabbed.classList.contains("is-dragging")).toBe(true)

    fire(grabbed, "dragend")
    expect(grabbed.classList.contains("is-dragging")).toBe(false)
  })

  it("clears the dragging state on drop", () => {
    vi.useFakeTimers()
    const grid = document.createElement("div")
    const grabbed = tile("1")
    grid.append(grabbed, tile("2"))
    document.body.append(grid)
    mount(grid)

    fire(grabbed, "dragstart")
    vi.runAllTimers()
    expect(grabbed.classList.contains("is-dragging")).toBe(true)

    fire(grid, "drop")
    expect(grabbed.classList.contains("is-dragging")).toBe(false)
  })
})
