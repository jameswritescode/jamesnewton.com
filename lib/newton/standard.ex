defmodule Newton.Standard do
  @moduledoc """
  Publishes site.standard.* records to the author's AT Protocol repo so
  ATmosphere apps can follow and discover the site. Documents are metadata
  only; readers follow the canonical URL to the site.
  """
  require Logger

  alias Newton.Blog.Post

  @spec put_document(%Post{}) :: :ok | {:error, term()}
  def put_document(%Post{} = post) do
    config = config()

    cond do
      !config[:enabled] ->
        :ok

      is_nil(config[:publication_uri]) ->
        Logger.error("standard.site is enabled but publication_uri is not configured")
        {:error, :publication_not_configured}

      true ->
        record = %{
          "$type" => "site.standard.document",
          "site" => config[:publication_uri],
          "title" => post.title,
          "path" => "/posts/#{post.slug}",
          "publishedAt" => DateTime.to_iso8601(post.published_at),
          "description" => post.excerpt
        }

        sync(:put_document, config, fn token ->
          xrpc(config, token, "com.atproto.repo.putRecord", %{
            repo: config[:did],
            collection: "site.standard.document",
            rkey: post.slug,
            record: record
          })
        end)
    end
  end

  @spec delete_document(String.t()) :: :ok | {:error, term()}
  def delete_document(slug) when is_binary(slug) do
    config = config()

    if config[:enabled] do
      sync(:delete_document, config, fn token ->
        xrpc(config, token, "com.atproto.repo.deleteRecord", %{
          repo: config[:did],
          collection: "site.standard.document",
          rkey: slug
        })
      end)
    else
      :ok
    end
  end

  @spec put_publication() :: {:ok, String.t()} | {:error, term()}
  def put_publication do
    config = config()

    record = %{
      "$type" => "site.standard.publication",
      "url" => "https://jamesnewton.com",
      "name" => "James Newton",
      "description" => "Software & Photography",
      "preferences" => %{"showInDiscover" => true}
    }

    result =
      sync(:put_publication, config, fn token ->
        xrpc(config, token, "com.atproto.repo.putRecord", %{
          repo: config[:did],
          collection: "site.standard.publication",
          rkey: "self",
          record: record
        })
      end)

    with :ok <- result do
      {:ok, "at://#{config[:did]}/site.standard.publication/self"}
    end
  end

  @spec publication_uri() :: String.t() | nil
  def publication_uri, do: config()[:publication_uri]

  @spec document_uri(String.t()) :: String.t() | nil
  def document_uri(slug) do
    with did when is_binary(did) <- config()[:did] do
      "at://#{did}/site.standard.document/#{slug}"
    end
  end

  defp sync(operation, config, fun) do
    Newton.Telemetry.span(:standard, :sync, %{operation: operation}, fn ->
      outcome =
        with {:ok, token} <- create_session(config) do
          fun.(token)
        end

      case outcome do
        :ok ->
          {:ok, %{operation: operation, result: :ok}}

        {:error, reason} ->
          Logger.warning("standard.site #{operation} failed: #{inspect(reason)}")
          {{:error, reason}, %{operation: operation, result: :error}}
      end
    end)
  end

  defp create_session(config) do
    body = %{identifier: config[:identifier], password: config[:app_password]}

    case Req.post(
           xrpc_url(config, "com.atproto.server.createSession"),
           [json: body] ++ req_options(config)
         ) do
      {:ok, %Req.Response{status: 200, body: %{"accessJwt" => token}}} -> {:ok, token}
      {:ok, %Req.Response{status: status}} -> {:error, {:session, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp xrpc(config, token, method, body) do
    case Req.post(
           xrpc_url(config, method),
           [json: body, auth: {:bearer, token}] ++ req_options(config)
         ) do
      {:ok, %Req.Response{status: status}} when status in 200..299 -> :ok
      {:ok, %Req.Response{status: status}} -> {:error, {:status, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp xrpc_url(config, method), do: "#{config[:pds_url]}/xrpc/#{method}"
  defp req_options(config), do: Keyword.get(config, :req_options, [])
  defp config, do: Application.get_env(:newton, __MODULE__, [])
end
