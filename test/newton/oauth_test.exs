defmodule Newton.OAuthTest do
  use Newton.DataCase, async: true

  alias Newton.OAuth

  @valid_registration %{
    "client_name" => "Claude",
    "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
    "token_endpoint_auth_method" => "client_secret_basic"
  }

  describe "register_client/1" do
    test "registers a confidential client and returns the secret exactly once" do
      assert {:ok, {client, secret}} = OAuth.register_client(@valid_registration)

      assert client.client_name == "Claude"
      assert client.redirect_uris == ["https://claude.ai/api/mcp/auth_callback"]
      assert is_binary(client.client_id)
      assert is_binary(secret)
      assert client.client_secret_hash == :crypto.hash(:sha256, secret)
    end

    test "registers a public client without a secret" do
      attrs = Map.put(@valid_registration, "token_endpoint_auth_method", "none")

      assert {:ok, {client, nil}} = OAuth.register_client(attrs)
      assert client.client_secret_hash == nil
    end

    test "defaults token_endpoint_auth_method to client_secret_basic" do
      attrs = Map.delete(@valid_registration, "token_endpoint_auth_method")

      assert {:ok, {client, secret}} = OAuth.register_client(attrs)
      assert client.token_endpoint_auth_method == "client_secret_basic"
      assert is_binary(secret)
    end

    test "rejects non-https redirect uris except loopback http" do
      for bad <- ["http://evil.example/cb", "ftp://x/cb", "not a url", "claude.ai/cb"] do
        attrs = Map.put(@valid_registration, "redirect_uris", [bad])
        assert {:error, changeset} = OAuth.register_client(attrs)
        assert %{redirect_uris: _} = errors_on(changeset)
      end

      for ok <- ["http://127.0.0.1:8976/cb", "http://localhost:33418/cb"] do
        attrs = Map.put(@valid_registration, "redirect_uris", [ok])
        assert {:ok, _} = OAuth.register_client(attrs)
      end
    end

    test "rejects empty redirect uri lists and unknown auth methods" do
      assert {:error, _} =
               OAuth.register_client(Map.put(@valid_registration, "redirect_uris", []))

      assert {:error, _} =
               OAuth.register_client(
                 Map.put(@valid_registration, "token_endpoint_auth_method", "private_key_jwt")
               )
    end
  end

  describe "authenticate_client/2" do
    test "authenticates a confidential client by secret" do
      {:ok, {client, secret}} = OAuth.register_client(@valid_registration)

      assert {:ok, authed} = OAuth.authenticate_client(client.client_id, secret)
      assert authed.id == client.id
      assert {:error, :invalid_client} = OAuth.authenticate_client(client.client_id, "wrong")
      assert {:error, :invalid_client} = OAuth.authenticate_client(client.client_id, nil)
    end

    test "authenticates a public client only without a secret" do
      attrs = Map.put(@valid_registration, "token_endpoint_auth_method", "none")
      {:ok, {client, nil}} = OAuth.register_client(attrs)

      assert {:ok, _} = OAuth.authenticate_client(client.client_id, nil)
      assert {:error, :invalid_client} = OAuth.authenticate_client(client.client_id, "anything")
    end

    test "unknown client_id fails closed" do
      assert {:error, :invalid_client} = OAuth.authenticate_client("nope", "secret")
    end
  end
end
