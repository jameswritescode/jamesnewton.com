defmodule Newton.SocialCard.Cache do
  @moduledoc """
  Memoizes rendered OG card PNGs so the public `/og/posts/:slug` endpoint does
  not run libvips on every request. Keyed by slug with the post's `updated_at`
  stored alongside, so an edited post re-renders while an unchanged one is
  served from memory. One entry per slug keeps the table bounded to the post
  count.
  """
  use GenServer

  @table __MODULE__

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Return the cached PNG for `{slug, version}`, or render it with `fun`, cache
  it, and return that. `version` is any term that changes when the card should
  (the post's `updated_at`).
  """
  @spec fetch(String.t(), term(), (-> {:ok, binary()} | {:error, term()})) ::
          {:ok, binary()} | {:error, term()}
  def fetch(slug, version, fun) do
    case :ets.lookup(@table, slug) do
      [{^slug, ^version, png}] ->
        {:ok, png}

      _ ->
        with {:ok, png} <- fun.() do
          :ets.insert(@table, {slug, version, png})
          {:ok, png}
        end
    end
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end
end
