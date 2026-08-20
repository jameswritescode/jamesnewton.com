defmodule NewtonWeb.OAuthController do
  use NewtonWeb, :controller

  alias Newton.OAuth
  alias Newton.OAuth.Client

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
          token_endpoint_auth_method: client.token_endpoint_auth_method,
          client_id_issued_at: DateTime.to_unix(client.inserted_at)
        }

        response =
          if secret,
            do: Map.merge(response, %{client_secret: secret, client_secret_expires_at: 0}),
            else: response

        conn |> put_no_store() |> put_status(201) |> json(response)

      {:error, _changeset} ->
        conn
        |> put_no_store()
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
      conn |> put_no_store() |> json(tokens)
    else
      error -> token_error(conn, error)
    end
  end

  def token(conn, %{"grant_type" => "refresh_token"} = params) do
    with {:ok, client} <- authenticated_client(conn, params),
         {:ok, tokens} <- OAuth.refresh(client, params["refresh_token"]) do
      conn |> put_no_store() |> json(tokens)
    else
      error -> token_error(conn, error)
    end
  end

  def token(conn, _params) do
    conn
    |> put_no_store()
    |> put_status(400)
    |> json(%{
      error: "unsupported_grant_type",
      error_description: "use authorization_code or refresh_token"
    })
  end

  defp authenticated_client(conn, params) do
    {basic_id, basic_secret, used_basic?} =
      case Plug.BasicAuth.parse_basic_auth(conn) do
        {id, secret} -> {id, secret, true}
        :error -> {nil, nil, false}
      end

    client_id = basic_id || params["client_id"]
    client = OAuth.get_client(client_id)

    case client_channel_secret(client, used_basic?, basic_secret, params["client_secret"]) do
      {:ok, secret} ->
        case OAuth.authenticate_client(client_id, secret) do
          {:ok, authenticated} ->
            {:ok, authenticated}

          {:error, :invalid_client} ->
            {:error, :invalid_client, used_basic?}
        end

      :error ->
        {:error, :invalid_client, used_basic?}
    end
  end

  defp client_channel_secret(
         %Client{token_endpoint_auth_method: "client_secret_basic"},
         true,
         basic_secret,
         nil
       ),
       do: {:ok, basic_secret}

  defp client_channel_secret(%Client{token_endpoint_auth_method: "client_secret_basic"}, _, _, _),
    do: :error

  defp client_channel_secret(
         %Client{token_endpoint_auth_method: "client_secret_post"},
         false,
         nil,
         body_secret
       ),
       do: {:ok, body_secret}

  defp client_channel_secret(%Client{token_endpoint_auth_method: "client_secret_post"}, _, _, _),
    do: :error

  defp client_channel_secret(%Client{token_endpoint_auth_method: "none"}, false, nil, nil),
    do: {:ok, nil}

  defp client_channel_secret(%Client{token_endpoint_auth_method: "none"}, _, _, _), do: :error

  defp client_channel_secret(nil, _used_basic?, basic_secret, body_secret),
    do: {:ok, basic_secret || body_secret}

  defp put_no_store(conn) do
    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_resp_header("pragma", "no-cache")
  end

  defp token_error(conn, {:error, :invalid_client, add_realm?}) do
    conn =
      if add_realm?,
        do: put_resp_header(conn, "www-authenticate", "Basic realm=\"oauth\""),
        else: conn

    conn
    |> put_no_store()
    |> put_status(401)
    |> json(%{error: "invalid_client", error_description: "client authentication failed"})
  end

  defp token_error(conn, {:error, :invalid_grant}) do
    conn
    |> put_no_store()
    |> put_status(400)
    |> json(%{
      error: "invalid_grant",
      error_description: "the grant is invalid, expired, or revoked"
    })
  end
end
