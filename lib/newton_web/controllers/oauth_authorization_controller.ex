defmodule NewtonWeb.OAuthAuthorizationController do
  use NewtonWeb, :controller

  plug :put_root_layout, html: {NewtonWeb.Layouts, :admin_root}

  alias Newton.OAuth

  def authorize(conn, params) do
    params = normalize_state(params)

    with {:ok, client, redirect_uri} <- fetch_client_and_redirect(params),
         :ok <- validate_request(params) do
      render(conn, :consent,
        client: client,
        redirect_uri: redirect_uri,
        redirect_host: URI.parse(redirect_uri).host,
        params: consent_params(params),
        page_title: "Authorize access"
      )
    else
      {:render_error, message} ->
        conn
        |> put_status(400)
        |> render(:error, message: message, page_title: "Authorization error")

      {:redirect_error, error} ->
        redirect_with_error(conn, params, error)
    end
  end

  def approve(conn, %{"decision" => "approve"} = params) do
    params = normalize_state(params)

    with {:ok, client, redirect_uri} <- fetch_client_and_redirect(params),
         :ok <- validate_request(params) do
      {:ok, code} =
        OAuth.issue_code(client, redirect_uri, params["code_challenge"], resource(params))

      redirect_back(conn, redirect_uri, %{"code" => code, "state" => params["state"]})
    else
      {:render_error, message} ->
        conn
        |> put_status(400)
        |> render(:error, message: message, page_title: "Authorization error")

      {:redirect_error, error} ->
        redirect_with_error(conn, params, error)
    end
  end

  def approve(conn, params) do
    params = normalize_state(params)

    case fetch_client_and_redirect(params) do
      {:ok, _client, redirect_uri} ->
        redirect_back(conn, redirect_uri, %{
          "error" => "access_denied",
          "state" => params["state"]
        })

      {:render_error, message} ->
        conn
        |> put_status(400)
        |> render(:error, message: message, page_title: "Authorization error")
    end
  end

  defp fetch_client_and_redirect(params) do
    client = OAuth.get_client(params["client_id"])

    cond do
      is_nil(client) ->
        {:render_error, "Unknown client. Check the client_id and register the client first."}

      not OAuth.redirect_uri_registered?(client, params["redirect_uri"]) ->
        {:render_error, "The redirect address is not registered for this client."}

      true ->
        {:ok, client, params["redirect_uri"]}
    end
  end

  defp validate_request(params) do
    cond do
      params["response_type"] != "code" -> {:redirect_error, "unsupported_response_type"}
      not is_binary(params["code_challenge"]) -> {:redirect_error, "invalid_request"}
      params["code_challenge"] == "" -> {:redirect_error, "invalid_request"}
      params["code_challenge_method"] != "S256" -> {:redirect_error, "invalid_request"}
      resource(params) != OAuth.canonical_resource() -> {:redirect_error, "invalid_target"}
      true -> :ok
    end
  end

  defp resource(params), do: params["resource"] || OAuth.canonical_resource()

  # State is echoed verbatim on every redirect but never stored. A non-binary
  # (`state[]=`) or over-long value is dropped rather than reflected: a
  # malformed request's own CSRF check fails on the client side, which is the
  # correct outcome for a request we can't faithfully round-trip.
  @max_state_length 1024

  defp normalize_state(%{"state" => state} = params)
       when not is_binary(state) or byte_size(state) > @max_state_length,
       do: Map.delete(params, "state")

  defp normalize_state(params), do: params

  defp redirect_with_error(conn, params, error) do
    redirect_back(conn, params["redirect_uri"], %{"error" => error, "state" => params["state"]})
  end

  defp redirect_back(conn, redirect_uri, query) do
    query = query |> Enum.reject(fn {_k, v} -> is_nil(v) end) |> URI.encode_query()

    location =
      redirect_uri
      |> URI.parse()
      |> URI.append_query(query)
      |> URI.to_string()

    redirect(conn, external: location)
  end

  defp consent_params(params) do
    Map.take(
      params,
      ~w(response_type client_id redirect_uri state code_challenge code_challenge_method resource)
    )
  end
end
