import {describe, it, expect, vi} from "vitest"
import {SortableGrid} from "./sortable_grid"

function tile(id) {
  const el = document.createElement("div")
  el.dataset.id = id
  return el
}

describe("SortableGrid", () => {
  it("pushes the current child id order on drop", () => {
    const grid = document.createElement("div")
    grid.append(tile("1"), tile("2"), tile("3"))
    const pushEvent = vi.fn()
    const hook = {el: grid, pushEvent}
    Object.setPrototypeOf(hook, SortableGrid)
    hook.mounted()

    const drop = new Event("drop", {bubbles: true})
    drop.preventDefault = () => {}
    grid.dispatchEvent(drop)

    expect(pushEvent).toHaveBeenCalledWith("reorder", {ids: ["1", "2", "3"]})
  })
})
