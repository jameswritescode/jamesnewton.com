defmodule Newton.Repo.Migrations.PurgePlaintextSessionTokens do
  use Ecto.Migration

  # Session tokens are now stored hashed, so rows written in the old format can
  # never match a presented token again. Delete them rather than leaving rows
  # that look like live sessions for the remainder of their 14-day window.
  # Everyone signed in at deploy time is signed out and logs in again.
  def up do
    execute "DELETE FROM users_tokens WHERE context = 'session'"
  end

  def down, do: :ok
end
