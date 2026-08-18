defmodule Newton.MCP.TokenValidatorTest do
  use Newton.DataCase, async: true

  alias Newton.MCP.TokenValidator
  alias Newton.OAuth

  defp valid_access_token do
    {:ok, {client, _secret}} =
      OAuth.register_client(%{
        "client_name" => "Claude",
        "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
        "token_endpoint_auth_method" => "none"
      })

    verifier = OAuth.generate_secret()
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    {:ok, code} =
      OAuth.issue_code(
        client,
        "https://claude.ai/api/mcp/auth_callback",
        challenge,
        OAuth.canonical_resource()
      )

    {:ok, %{access_token: token}} =
      OAuth.exchange_code(client, code, "https://claude.ai/api/mcp/auth_callback", verifier)

    token
  end

  test "accepts a live token bound to the MCP resource" do
    assert {:ok, claims} = TokenValidator.validate_token(valid_access_token(), [])
    assert claims["aud"] == OAuth.canonical_resource()
  end

  test "rejects garbage and empty tokens" do
    assert {:error, _} = TokenValidator.validate_token("garbage", [])
    assert {:error, _} = TokenValidator.validate_token("", [])
  end
end
