import {describe, it, expect, afterEach} from "vitest"
import {fillDerived, installFillDerived} from "./fill_derived"

function field(id, value = "") {
  const el = document.createElement("input")
  el.id = id
  el.value = value
  document.body.appendChild(el)
  return el
}

afterEach(() => {
  document.activeElement?.blur()
  document.body.innerHTML = ""
})

describe("fillDerived", () => {
  it("fills a blank field that is not focused", () => {
    const el = field("post_excerpt")

    fillDerived({id: "post_excerpt", value: "Seed body."})

    expect(el.value).toBe("Seed body.")
  })

  it("waits for a focused field to blur, then fills it if still blank", () => {
    const el = field("post_slug")
    el.focus()

    fillDerived({id: "post_slug", value: "custom-draft"})
    expect(el.value).toBe("")

    el.blur()
    expect(el.value).toBe("custom-draft")
  })

  it("leaves a focused field alone when the author types before blurring", () => {
    const el = field("post_slug")
    el.focus()

    fillDerived({id: "post_slug", value: "custom-draft"})
    el.value = "my-own"
    el.blur()

    expect(el.value).toBe("my-own")
  })

  it("never overwrites a field that has text", () => {
    const el = field("post_excerpt", "Mine")

    fillDerived({id: "post_excerpt", value: "Seed body."})

    expect(el.value).toBe("Mine")
  })

  it("does nothing when the field is missing", () => {
    expect(() => fillDerived({id: "nope", value: "x"})).not.toThrow()
  })
})

describe("installFillDerived", () => {
  it("fills fields from phx:fill_derived window events", () => {
    const el = field("page_meta_description")
    installFillDerived(window)

    window.dispatchEvent(
      new CustomEvent("phx:fill_derived", {detail: {id: "page_meta_description", value: "Hi."}}),
    )

    expect(el.value).toBe("Hi.")
  })
})
