defmodule Newton.Webauthn do
  @moduledoc """
  Thin wrapper over Wax: applies our configured rp_id/origin.

  ## Confirmed Wax 0.7 field paths (verified from deps/wax_/lib/):

  ### Registration — `Wax.register/3`
  Returns `{:ok, {%Wax.AuthenticatorData{}, attestation_result}}` where:
    - credential id:     `auth_data.attested_credential_data.credential_id`       (binary)
    - COSE public key:   `auth_data.attested_credential_data.credential_public_key` (map)
    - signature counter: `auth_data.sign_count`                                    (non_neg_integer)

  ### Authentication — `Wax.authenticate/6`
  Returns `{:ok, %Wax.AuthenticatorData{}}` where:
    - signature counter: `auth_data.sign_count`                                    (non_neg_integer)

  ### Challenge fields
  - Raw challenge bytes: `challenge.bytes`   (binary, 32 random bytes)
  - Relying-party ID:    `challenge.rp_id`   (string)
  """

  def opts(extra \\ []) do
    cfg = Application.fetch_env!(:newton, :webauthn)
    Keyword.merge([rp_id: cfg[:rp_id], origin: cfg[:origin]], extra)
  end

  def registration_challenge, do: Wax.new_registration_challenge(opts())

  @doc """
  Creates a new authentication challenge for the discoverable/usernameless passkey flow.

  Sets `allow_credentials: []` which tells the authenticator it may use any resident key
  for this relying party (i.e. the browser shows its own account picker). Because no
  credentials are bound to the challenge, the caller **must** supply the matching
  `{credential_id, cose_key}` pairs explicitly when verifying the assertion:

      Wax.authenticate(credential_id, auth_data, sig, client_data_json, challenge, credentials)

  where `credentials` is a list of `{credential_id_binary, cose_key_map}` tuples looked up
  from the database after the authenticator returns its `credential_id`.  The challenge alone
  does not bind to any user's credentials — that binding happens at verification time.
  """
  def authentication_challenge, do: Wax.new_authentication_challenge(opts(allow_credentials: []))

  def dump_key(cose_key), do: :erlang.term_to_binary(cose_key)
  def load_key(bin), do: :erlang.binary_to_term(bin, [:safe])
end
