import {bufToB64url, b64urlToBuf} from "../webauthn"

// Sudo-page hook: re-authenticate with a passkey. Reuses the login challenge
// endpoint, then POSTs the assertion to the sudo verifier (which confirms the
// credential belongs to the current user) and navigates back on success.
async function run(returnTo) {
  const res = await fetch("/login/passkey/challenge", {headers: {accept: "application/json"}})
  const {challenge, rpId, userVerification} = await res.json()

  const cred = await navigator.credentials.get({
    publicKey: {
      challenge: b64urlToBuf(challenge),
      rpId,
      userVerification,
      allowCredentials: [],
    },
  })

  const token = document.querySelector("meta[name='csrf-token']").content
  const out = await fetch("/login/confirm-access/passkey", {
    method: "POST",
    headers: {"content-type": "application/json", "x-csrf-token": token},
    body: JSON.stringify({
      id: bufToB64url(cred.rawId),
      authenticatorData: bufToB64url(cred.response.authenticatorData),
      clientDataJSON: bufToB64url(cred.response.clientDataJSON),
      signature: bufToB64url(cred.response.signature),
      return_to: returnTo,
    }),
  })

  if (out.ok) {
    const {to} = await out.json()
    window.location.assign(to)
  }
}

export const PasskeySudo = {
  mounted() {
    this.el.addEventListener("click", () => run(this.el.dataset.returnTo).catch(() => {}))
  },
}
