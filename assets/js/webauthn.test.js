import {describe, it, expect} from "vitest"
import {bufToB64url, b64urlToBuf} from "./webauthn"

describe("webauthn base64url helpers", () => {
  it("round-trips arbitrary bytes through encode/decode", () => {
    const bytes = new Uint8Array([0, 1, 2, 127, 128, 200, 255, 65, 66])
    const restored = new Uint8Array(b64urlToBuf(bufToB64url(bytes.buffer)))
    expect([...restored]).toEqual([...bytes])
  })

  it("encodes with a url-safe alphabet and no padding", () => {
    // 0xfb 0xff 0xbf -> standard base64 "+/+/", url-safe "-_-_" (no '=' padding)
    const encoded = bufToB64url(new Uint8Array([0xfb, 0xff, 0xbf]).buffer)
    expect(encoded).toBe("-_-_")
    expect(encoded).not.toMatch(/[+/=]/)
  })

  it("decodes a known base64url string to the expected bytes", () => {
    const bytes = new Uint8Array(b64urlToBuf("AQIDBA")) // [1,2,3,4]
    expect([...bytes]).toEqual([1, 2, 3, 4])
  })
})
