defmodule NewtonWeb.SudoController do
  @moduledoc """
  Re-authentication (sudo mode) for the already-logged-in admin. Verifying the
  password or a passkey rotates the session token, which refreshes
  `authenticated_at` and reopens the sudo window guarding sensitive settings.
  """
  use NewtonWeb, :controller

  alias Newton.Accounts
  alias NewtonWeb.UserAuth

  # The only sudo-gated page today; where a successful re-auth returns.
  @return_to "/admin/settings"

  def password(conn, %{"user" => %{"password" => password}}) do
    email = conn.assigns.current_scope.user.email

    # The verified user carries no authenticated_at, so the rotated token stamps
    # a fresh one — that's what reopens the sudo window.
    if user = Accounts.get_user_by_email_and_password(email, password) do
      conn
      |> UserAuth.log_in_user_session(user, %{"remember_me" => "true"})
      |> redirect(to: @return_to)
    else
      conn
      |> put_flash(:error, "That password didn't match.")
      |> redirect(to: ~p"/login/confirm-access")
    end
  end

  def passkey(conn, %{
        "id" => raw_id,
        "authenticatorData" => auth_data_b64,
        "clientDataJSON" => cdj_b64,
        "signature" => sig_b64
      }) do
    user = conn.assigns.current_scope.user
    challenge = get_session(conn, :passkey_challenge)

    with false <- is_nil(challenge),
         {:ok, cred_id} <- Base.url_decode64(raw_id, padding: false),
         %{} = cred <- Accounts.get_credential_by_external_id(cred_id),
         true <- cred.user.id == user.id,
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
      |> UserAuth.log_in_user_session(cred.user, %{"remember_me" => "true"})
      |> json(%{ok: true, to: @return_to})
    else
      _ ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "Passkey verification failed."})
    end
  end
end
