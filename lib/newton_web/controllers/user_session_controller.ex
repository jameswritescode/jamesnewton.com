defmodule NewtonWeb.UserSessionController do
  use NewtonWeb, :controller

  alias Newton.Accounts
  alias NewtonWeb.UserAuth

  # email + password login
  def create(conn, %{"user" => user_params}) do
    %{"email" => email, "password" => password} = user_params

    if user = Accounts.get_user_by_email_and_password(email, password) do
      if Accounts.has_passkey?(user) do
        conn
        |> put_session(:pending_2fa_user_id, user.id)
        |> put_session(:pending_2fa_remember_me, user_params["remember_me"] == "true")
        |> redirect(to: ~p"/login/verify")
      else
        conn |> put_flash(:info, "Welcome back!") |> UserAuth.log_in_user(user, user_params)
      end
    else
      # In order to prevent user enumeration attacks, don't disclose whether the email is registered.
      conn
      |> put_flash(:error, "Invalid email or password")
      |> put_flash(:email, String.slice(email, 0, 160))
      |> redirect(to: ~p"/login")
    end
  end

  def recovery_login(conn, %{"code" => code}) do
    case get_session(conn, :pending_2fa_user_id) do
      nil ->
        redirect(conn, to: ~p"/login")

      user_id ->
        user = Accounts.get_user!(user_id)

        case Accounts.redeem_recovery_code(user, code) do
          :ok ->
            remember = get_session(conn, :pending_2fa_remember_me)

            conn
            |> put_flash(:info, "Welcome back!")
            |> UserAuth.log_in_user(user, %{"remember_me" => to_string(remember)})

          :error ->
            conn
            |> put_flash(:error, "That code didn't work. Try another.")
            |> redirect(to: ~p"/login/verify")
        end
    end
  end

  # Issue a usernameless (discoverable-credential) authentication challenge and
  # stash it in the session for the matching POST below to verify against.
  def passkey_challenge(conn, _params) do
    challenge = Newton.Webauthn.authentication_challenge()

    conn
    |> put_session(:passkey_challenge, challenge)
    |> json(%{
      challenge: Base.url_encode64(challenge.bytes, padding: false),
      rpId: challenge.rp_id,
      userVerification: "preferred"
    })
  end

  def passkey_login(conn, %{
        "id" => raw_id,
        "authenticatorData" => auth_data_b64,
        "clientDataJSON" => cdj_b64,
        "signature" => sig_b64
      }) do
    challenge = get_session(conn, :passkey_challenge)

    with false <- is_nil(challenge),
         {:ok, cred_id} <- Base.url_decode64(raw_id, padding: false),
         %{} = cred <- Accounts.get_credential_by_external_id(cred_id),
         {:ok, auth_data_bin} <- Base.url_decode64(auth_data_b64, padding: false),
         {:ok, sig} <- Base.url_decode64(sig_b64, padding: false),
         {:ok, client_data} <- Base.url_decode64(cdj_b64, padding: false),
         {:ok, auth_data} <-
           Wax.authenticate(cred_id, auth_data_bin, sig, client_data, challenge, [
             {cred_id, Newton.Webauthn.load_key(cred.public_key)}
           ]),
         true <- auth_data.sign_count >= cred.sign_count do
      {:ok, _} =
        Accounts.update_credential_sign_count(
          cred,
          auth_data.sign_count,
          DateTime.truncate(DateTime.utc_now(), :second)
        )

      conn
      |> delete_session(:passkey_challenge)
      |> UserAuth.log_in_user_session(cred.user)
      |> json(%{ok: true, to: UserAuth.signed_in_path(conn)})
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Passkey authentication failed."})
    end
  end

  def delete(conn, _params) do
    conn
    |> put_flash(:info, "Logged out successfully.")
    |> UserAuth.log_out_user()
  end
end
