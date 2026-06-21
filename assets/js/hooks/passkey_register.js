import {bufToB64url, b64urlToBuf} from "../webauthn"

// Settings-page hook: the server pushes "passkey_create" with the
// PublicKeyCredentialCreationOptions (challenge/user.id/excludeCredentials
// base64url-encoded). We run navigator.credentials.create and send the
// attestation back for Wax to verify, tagging it with the label the author typed.
export const PasskeyRegister = {
  mounted() {
    this.handleEvent("passkey_create", async (opts) => {
      try {
        const publicKey = {
          ...opts,
          challenge: b64urlToBuf(opts.challenge),
          user: {...opts.user, id: b64urlToBuf(opts.user.id)},
          excludeCredentials: (opts.excludeCredentials || []).map((c) => ({
            ...c,
            id: b64urlToBuf(c.id),
          })),
        }
        const cred = await navigator.credentials.create({publicKey})
        this.pushEvent("passkey_registered", {
          rawId: bufToB64url(cred.rawId),
          clientDataJSON: bufToB64url(cred.response.clientDataJSON),
          attestationObject: bufToB64url(cred.response.attestationObject),
          label: this.el.dataset.label || "",
        })
      } catch (e) {
        this.pushEvent("passkey_error", {message: String(e)})
      }
    })
  },
}
