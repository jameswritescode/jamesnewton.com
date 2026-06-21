import {bufToB64url, b64urlToBuf} from "../webauthn"

// Login-page hook. Drives the passwordless passkey ceremony: fetch a challenge,
// run navigator.credentials.get, POST the assertion, and navigate on success.
async function runCeremony(mediation) {
  const res = await fetch("/login/passkey/challenge", {headers: {accept: "application/json"}})
  const {challenge, rpId, userVerification} = await res.json()

  const cred = await navigator.credentials.get({
    mediation,
    publicKey: {
      challenge: b64urlToBuf(challenge),
      rpId,
      userVerification,
      allowCredentials: [],
    },
  })

  const token = document.querySelector("meta[name='csrf-token']").content
  const out = await fetch("/login/passkey", {
    method: "POST",
    headers: {"content-type": "application/json", "x-csrf-token": token},
    body: JSON.stringify({
      id: bufToB64url(cred.rawId),
      authenticatorData: bufToB64url(cred.response.authenticatorData),
      clientDataJSON: bufToB64url(cred.response.clientDataJSON),
      signature: bufToB64url(cred.response.signature),
      userHandle: cred.response.userHandle ? bufToB64url(cred.response.userHandle) : null,
    }),
  })

  if (out.ok) {
    const {to} = await out.json()
    window.location.assign(to)
  }
}

export const PasskeyAuthenticate = {
  async mounted() {
    // Conditional UI: surfaces passkeys as autofill on the username field with
    // no button press. Only on browsers that support it.
    if (window.PublicKeyCredential?.isConditionalMediationAvailable) {
      const available = await PublicKeyCredential.isConditionalMediationAvailable().catch(
        () => false
      )
      if (available) runCeremony("conditional").catch(() => {})
    }

    // Explicit fallback for browsers without conditional mediation.
    const button = document.getElementById("passkey-button")
    if (button) {
      button.addEventListener("click", () => runCeremony("optional").catch(() => {}))
    }
  },
}
