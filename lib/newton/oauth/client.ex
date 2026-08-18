defmodule Newton.OAuth.Client do
  use Ecto.Schema
  import Ecto.Changeset

  @auth_methods ~w(none client_secret_post client_secret_basic)

  schema "oauth_clients" do
    field :client_id, :string
    field :client_secret_hash, :binary
    field :client_name, :string
    field :redirect_uris, {:array, :string}
    field :token_endpoint_auth_method, :string, default: "client_secret_basic"

    timestamps(type: :utc_datetime)
  end

  @doc false
  @spec registration_changeset(%__MODULE__{}, map()) :: Ecto.Changeset.t()
  def registration_changeset(client, attrs) do
    client
    |> cast(attrs, [:client_name, :redirect_uris, :token_endpoint_auth_method])
    |> validate_required([:client_name, :redirect_uris])
    |> validate_length(:redirect_uris, min: 1)
    |> validate_inclusion(:token_endpoint_auth_method, @auth_methods)
    |> validate_change(:redirect_uris, &validate_redirect_uris/2)
  end

  defp validate_redirect_uris(:redirect_uris, uris) do
    if Enum.all?(uris, &allowed_redirect_uri?/1),
      do: [],
      else: [redirect_uris: "must be absolute https URLs (or http loopback)"]
  end

  defp allowed_redirect_uri?(uri) do
    case URI.new(uri) do
      {:ok, %URI{scheme: "https", host: host}} when is_binary(host) and host != "" -> true
      {:ok, %URI{scheme: "http", host: host}} -> host in ["127.0.0.1", "localhost", "::1"]
      _ -> false
    end
  end
end
