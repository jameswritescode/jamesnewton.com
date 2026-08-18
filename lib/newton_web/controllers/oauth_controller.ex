defmodule NewtonWeb.OAuthController do
  use NewtonWeb, :controller

  alias Newton.OAuth

  def authorization_server_metadata(conn, _params) do
    base = NewtonWeb.Endpoint.url()

    json(conn, %{
      issuer: base,
      authorization_endpoint: base <> "/oauth/authorize",
      token_endpoint: base <> "/oauth/token",
      registration_endpoint: base <> "/oauth/register",
      grant_types_supported: ["authorization_code", "refresh_token"],
      response_types_supported: ["code"],
      code_challenge_methods_supported: ["S256"],
      token_endpoint_auth_methods_supported: ["none", "client_secret_post", "client_secret_basic"]
    })
  end

  def register(conn, params) do
    case OAuth.register_client(params) do
      {:ok, {client, secret}} ->
        response = %{
          client_id: client.client_id,
          client_name: client.client_name,
          redirect_uris: client.redirect_uris,
          token_endpoint_auth_method: client.token_endpoint_auth_method
        }

        response = if secret, do: Map.put(response, :client_secret, secret), else: response

        conn |> put_status(201) |> json(response)

      {:error, _changeset} ->
        conn
        |> put_status(400)
        |> json(%{error: "invalid_client_metadata", error_description: "invalid registration"})
    end
  end
end
