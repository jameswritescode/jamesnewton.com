defmodule Newton.MCP.TokenValidator do
  @moduledoc "Anubis bearer validator backed by Newton.OAuth's hashed token store."

  @behaviour Anubis.Server.Authorization.Validator

  alias Newton.OAuth

  @impl true
  def validate_token(token, _config) do
    with {:ok, claims} <- OAuth.verify_access_token(token),
         true <- claims["aud"] == OAuth.canonical_resource() do
      {:ok, claims}
    else
      _ -> {:error, :invalid_token}
    end
  end
end
