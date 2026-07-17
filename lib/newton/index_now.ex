defmodule Newton.IndexNow do
  @moduledoc """
  Submits changed public URLs to the IndexNow API so participating engines
  (Bing, Yandex, Seznam, Naver) recrawl promptly. Google does not participate;
  it discovers changes through the sitemap.
  """
  require Logger

  @endpoint "https://api.indexnow.org/indexnow"

  @spec submit([String.t()]) :: :ok | {:error, term()}
  def submit([]), do: :ok

  def submit(urls) do
    config = Application.get_env(:newton, __MODULE__, [])

    if config[:enabled] do
      do_submit(urls, config)
    else
      :ok
    end
  end

  defp do_submit(urls, config) do
    Newton.Telemetry.span(:indexnow, :submit, %{url_count: length(urls)}, fn ->
      body = %{host: URI.parse(hd(urls)).host, key: config[:key], urlList: urls}

      {outcome, status} =
        case Req.post(@endpoint, [json: body] ++ Keyword.get(config, :req_options, [])) do
          {:ok, %Req.Response{status: status}} when status in 200..299 ->
            {:ok, status}

          {:ok, %Req.Response{status: status}} ->
            Logger.warning("IndexNow rejected submission (status #{status}): #{inspect(urls)}")
            {{:error, {:status, status}}, status}

          {:error, reason} ->
            Logger.warning(
              "IndexNow submission failed: #{inspect(reason)} urls: #{inspect(urls)}"
            )

            {{:error, reason}, nil}
        end

      result = if outcome == :ok, do: :ok, else: :error
      {outcome, %{result: result, status: status, url_count: length(urls)}}
    end)
  end
end
