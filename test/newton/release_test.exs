defmodule Newton.ReleaseTest do
  use Newton.DataCase, async: true

  alias Newton.Accounts
  alias Newton.Release

  describe "create_admin/2" do
    test "creates a confirmed user that can authenticate with email + password" do
      {:ok, user} = Release.create_admin("owner@example.com", "supersecret123")

      assert user.email == "owner@example.com"
      assert user.confirmed_at
      assert Accounts.get_user_by_email_and_password("owner@example.com", "supersecret123")
    end

    test "returns an error changeset for an invalid email" do
      assert {:error, %Ecto.Changeset{}} = Release.create_admin("nope", "supersecret123")
    end
  end
end
