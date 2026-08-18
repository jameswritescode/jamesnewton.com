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

  def token(conn, %{"grant_type" => "authorization_code"} = params) do
    with {:ok, client} <- authenticated_client(conn, params),
         {:ok, tokens} <-
           OAuth.exchange_code(
             client,
             params["code"],
             params["redirect_uri"],
             params["code_verifier"]
           ) do
      json(conn, tokens)
    else
      error -> token_error(conn, error)
    end
  end

  def token(conn, %{"grant_type" => "refresh_token"} = params) do
    with {:ok, client} <- authenticated_client(conn, params),
         {:ok, tokens} <- OAuth.refresh(client, params["refresh_token"]) do
      json(conn, tokens)
    else
      error -> token_error(conn, error)
    end
  end

  def token(conn, _params) do
    conn
    |> put_status(400)
    |> json(%{
      error: "unsupported_grant_type",
      error_description: "use authorization_code or refresh_token"
    })
  end

  defp authenticated_client(conn, params) do
    {client_id, secret} =
      case Plug.BasicAuth.parse_basic_auth(conn) do
        {basic_id, basic_secret} -> {basic_id, basic_secret}
        :error -> {params["client_id"], params["client_secret"]}
      end

    OAuth.authenticate_client(client_id, secret)
  end

  defp token_error(conn, {:error, :invalid_client}) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"oauth\"")
    |> put_status(401)
    |> json(%{error: "invalid_client", error_description: "client authentication failed"})
  end

  defp token_error(conn, {:error, :invalid_grant}) do
    conn
    |> put_status(400)
    |> json(%{
      error: "invalid_grant",
      error_description: "the grant is invalid, expired, or revoked"
    })
  end
end
