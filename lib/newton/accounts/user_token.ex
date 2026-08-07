defmodule Newton.Accounts.UserToken do
  use Ecto.Schema
  import Ecto.Query
  alias Newton.Accounts.UserToken

  @hash_algorithm :sha256
  @rand_size 32

  @change_email_validity_in_days 7
  @session_validity_in_days 14

  schema "users_tokens" do
    field :token, :binary
    field :context, :string
    field :sent_to, :string
    field :authenticated_at, :utc_datetime
    belongs_to :user, Newton.Accounts.User

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Generates a session token, returning the value for the cookie alongside the
  row to persist.

  Session tokens are stored in the database — rather than relying on Phoenix's
  signed cookie alone — so that individual sessions can be expired. Only the
  hash is persisted: the cookie already travels signed and encrypted, so the
  database never needs the value that would let a reader resume a live session.
  """
  @spec build_session_token(%Newton.Accounts.User{}) :: {binary(), %__MODULE__{}}
  def build_session_token(user) do
    token = :crypto.strong_rand_bytes(@rand_size)
    dt = user.authenticated_at || DateTime.utc_now(:second)

    {token,
     %UserToken{
       token: hash_token(token),
       context: "session",
       user_id: user.id,
       authenticated_at: dt
     }}
  end

  @doc "The stored form of a session token. Also names its PubSub disconnect topic."
  @spec hash_token(binary()) :: binary()
  def hash_token(token), do: :crypto.hash(@hash_algorithm, token)

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user found by the token, if any, along with the token's creation time.

  The token is valid if it matches the value in the database and it has
  not expired (after @session_validity_in_days).
  """
  @spec verify_session_token_query(binary()) :: {:ok, Ecto.Query.t()}
  def verify_session_token_query(token) do
    query =
      from token in by_token_and_context_query(hash_token(token), "session"),
        join: user in assoc(token, :user),
        where: token.inserted_at > ago(@session_validity_in_days, "day"),
        select: {%{user | authenticated_at: token.authenticated_at}, token.inserted_at}

    {:ok, query}
  end

  @doc """
  Builds a token and its hash to be delivered to the user's email.

  The non-hashed token is sent to the user email while the
  hashed part is stored in the database. The original token cannot be reconstructed,
  which means anyone with read-only access to the database cannot directly use
  the token in the application to gain access. Furthermore, if the user changes
  their email in the system, the tokens sent to the previous email are no longer
  valid.

  Users can easily adapt the existing code to provide other types of delivery methods,
  for example, by phone numbers.
  """
  @spec build_email_token(%Newton.Accounts.User{}, String.t()) :: {String.t(), %__MODULE__{}}
  def build_email_token(user, context) do
    build_hashed_token(user, context, user.email)
  end

  defp build_hashed_token(user, context, sent_to) do
    token = :crypto.strong_rand_bytes(@rand_size)
    hashed_token = :crypto.hash(@hash_algorithm, token)

    {Base.url_encode64(token, padding: false),
     %UserToken{
       token: hashed_token,
       context: context,
       sent_to: sent_to,
       user_id: user.id
     }}
  end

  @doc """
  Checks if the token is valid and returns its underlying lookup query.

  The query returns the user_token found by the token, if any.

  This is used to validate requests to change the user
  email.
  The given token is valid if it matches its hashed counterpart in the
  database and if it has not expired (after @change_email_validity_in_days).
  The context must always start with "change:".
  """
  @spec verify_change_email_token_query(String.t(), String.t()) :: {:ok, Ecto.Query.t()} | :error
  def verify_change_email_token_query(token, "change:" <> _ = context) do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded_token} ->
        hashed_token = :crypto.hash(@hash_algorithm, decoded_token)

        query =
          from token in by_token_and_context_query(hashed_token, context),
            where: token.inserted_at > ago(@change_email_validity_in_days, "day")

        {:ok, query}

      :error ->
        :error
    end
  end

  defp by_token_and_context_query(token, context) do
    from UserToken, where: [token: ^token, context: ^context]
  end
end
