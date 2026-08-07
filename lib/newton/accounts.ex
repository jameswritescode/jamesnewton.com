defmodule Newton.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Newton.Repo

  alias Newton.Accounts.{Credential, RecoveryCode, User, UserNotifier, UserToken}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  @spec get_user_by_email(String.t()) :: %User{} | nil
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  @spec get_user_by_email_and_password(String.t(), String.t()) :: %User{} | nil
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  @spec get_user!(integer()) :: %User{}
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  @spec register_user(map()) :: {:ok, %User{}} | {:error, Ecto.Changeset.t()}
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  @spec sudo_mode?(%User{}, integer()) :: boolean()
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Newton.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_email(%User{}, map(), keyword()) :: Ecto.Changeset.t()
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  @spec update_user_email(%User{}, String.t()) :: {:ok, %User{}} | {:error, :transaction_aborted}
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transact(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        {:ok, user}
      else
        _ -> {:error, :transaction_aborted}
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  See `Newton.Accounts.User.password_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  @spec change_user_password(%User{}, map(), keyword()) :: Ecto.Changeset.t()
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.

  Returns a tuple with the updated user, as well as a list of expired tokens.

  ## Examples

      iex> update_user_password(user, %{password: ...})
      {:ok, {%User{}, [...]}}

      iex> update_user_password(user, %{password: "too short"})
      {:error, %Ecto.Changeset{}}

  """
  @spec update_user_password(%User{}, map()) ::
          {:ok, {%User{}, [%UserToken{}]}} | {:error, Ecto.Changeset.t()}
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc "Change the password after verifying the supplied current password."
  @spec update_user_password(%User{}, String.t(), map()) ::
          {:ok, {%User{}, [%UserToken{}]}} | {:error, Ecto.Changeset.t()}
  def update_user_password(user, current_password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> maybe_validate_current_password(user, current_password)

    if changeset.valid? do
      update_user_and_delete_all_tokens(changeset)
    else
      {:error, %{changeset | action: :update}}
    end
  end

  defp maybe_validate_current_password(changeset, user, current_password) do
    if User.valid_password?(user, current_password) do
      changeset
    else
      Ecto.Changeset.add_error(changeset, :current_password, "is not valid")
    end
  end

  @spec update_user_timezone(%User{}, map()) :: {:ok, %User{}} | {:error, Ecto.Changeset.t()}
  def update_user_timezone(%User{} = user, attrs) do
    user |> User.timezone_changeset(attrs) |> Repo.update()
  end

  ## Session

  @doc """
  Generates a session token.
  """
  @spec generate_user_session_token(%User{}) :: binary()
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  @spec get_user_by_session_token(binary()) :: {%User{}, DateTime.t()} | nil
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  @spec deliver_user_update_email_instructions(%User{}, String.t(), (String.t() -> String.t())) ::
          {:ok, Swoosh.Email.t()} | {:error, term()}
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  @spec delete_user_session_token(binary()) :: :ok
  def delete_user_session_token(token) do
    hashed = UserToken.hash_token(token)
    Repo.delete_all(from(UserToken, where: [token: ^hashed, context: "session"]))
    :ok
  end

  ## Token helper

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transact(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all_by(UserToken, user_id: user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {:ok, {user, tokens_to_expire}}
      end
    end)
  end

  ## Credentials

  @spec list_user_credentials(%User{}) :: [%Credential{}]
  def list_user_credentials(%User{id: id}) do
    Repo.all(from c in Credential, where: c.user_id == ^id, order_by: [desc: c.inserted_at])
  end

  @doc """
  Looks up a credential by its WebAuthn credential ID, preloading `:user`.

  Intentionally unscoped — returns credentials belonging to any user. This is
  correct for the passkey authentication flow: the authenticator presents its
  credential ID before we know who the user is, and the caller verifies identity
  through the assertion signature rather than through an ownership check here.
  """
  @spec get_credential_by_external_id(binary()) :: %Credential{} | nil
  def get_credential_by_external_id(credential_id) do
    Repo.one(from c in Credential, where: c.credential_id == ^credential_id, preload: :user)
  end

  @spec create_credential(%User{}, map()) :: {:ok, %Credential{}} | {:error, Ecto.Changeset.t()}
  def create_credential(%User{id: user_id}, attrs) do
    %Credential{user_id: user_id}
    |> Credential.label_changeset(Map.take(attrs, [:label]))
    |> Ecto.Changeset.put_change(:credential_id, attrs.credential_id)
    |> Ecto.Changeset.put_change(:public_key, attrs.public_key)
    |> Ecto.Changeset.put_change(:sign_count, attrs.sign_count)
    |> Repo.insert()
  end

  @spec update_credential_sign_count(%Credential{}, non_neg_integer(), DateTime.t()) ::
          {:ok, %Credential{}} | {:error, Ecto.Changeset.t()}
  def update_credential_sign_count(%Credential{} = cred, count, used_at) do
    cred
    |> Ecto.Changeset.change(sign_count: count, last_used_at: used_at)
    |> Repo.update()
  end

  @spec delete_credential(%User{}, term()) ::
          {:ok, %Credential{}} | {:error, Ecto.Changeset.t()} | :error
  def delete_credential(%User{id: user_id}, id) do
    case Repo.get_by(Credential, id: id, user_id: user_id) do
      nil -> :error
      cred -> Repo.delete(cred)
    end
  end

  @doc "True if the user has at least one passkey credential."
  @spec has_passkey?(%User{}) :: boolean()
  def has_passkey?(%User{id: id}), do: Repo.exists?(from c in Credential, where: c.user_id == ^id)

  ## Recovery codes

  # Unambiguous alphabet (no 0/O/1/I/L/U); 10 chars shown as `xxxxx-xxxxx`.
  @recovery_alphabet ~c"23456789ABCDEFGHJKMNPQRSTVWXYZ"
  @recovery_alphabet_length length(@recovery_alphabet)
  @recovery_count 10

  @doc "Replace the user's recovery codes with 10 fresh ones; returns the plaintext codes."
  @spec generate_recovery_codes(%User{}) :: [String.t()]
  def generate_recovery_codes(%User{id: user_id}) do
    codes = for _ <- 1..@recovery_count, do: random_recovery_code()
    now = DateTime.truncate(DateTime.utc_now(), :second)

    rows =
      Enum.map(codes, fn code ->
        %{
          user_id: user_id,
          code_hash: hash_recovery_code(code),
          inserted_at: now,
          updated_at: now
        }
      end)

    {:ok, _} =
      Repo.transact(fn ->
        Repo.delete_all(from r in RecoveryCode, where: r.user_id == ^user_id)
        Repo.insert_all(RecoveryCode, rows)
        {:ok, codes}
      end)

    codes
  end

  @doc "How many of the user's recovery codes are still unused."
  @spec count_unused_recovery_codes(%User{}) :: non_neg_integer()
  def count_unused_recovery_codes(%User{id: user_id}) do
    Repo.aggregate(
      from(r in RecoveryCode, where: r.user_id == ^user_id and is_nil(r.used_at)),
      :count
    )
  end

  @doc "Consume a matching unused recovery code; `:ok` if exactly one was spent, else `:error`."
  @spec redeem_recovery_code(%User{}, String.t()) :: :ok | :error
  def redeem_recovery_code(%User{id: user_id}, code) when is_binary(code) do
    normalized = normalize_recovery_code(code)
    now = DateTime.truncate(DateTime.utc_now(), :second)

    candidates =
      Repo.all(from r in RecoveryCode, where: r.user_id == ^user_id and is_nil(r.used_at))

    case Enum.find(candidates, &Bcrypt.verify_pass(normalized, &1.code_hash)) do
      nil ->
        Bcrypt.no_user_verify()
        :error

      %RecoveryCode{id: id} ->
        {count, _} =
          Repo.update_all(
            from(r in RecoveryCode, where: r.id == ^id and is_nil(r.used_at)),
            set: [used_at: now, updated_at: now]
          )

        if count == 1, do: :ok, else: :error
    end
  end

  defp random_recovery_code do
    chars =
      :crypto.strong_rand_bytes(10)
      |> :binary.bin_to_list()
      |> Enum.map(&Enum.at(@recovery_alphabet, rem(&1, @recovery_alphabet_length)))
      |> List.to_string()

    String.slice(chars, 0, 5) <> "-" <> String.slice(chars, 5, 5)
  end

  # Normalize (upcase, strip non-alphanumerics) before hashing so lenient input matches.
  defp normalize_recovery_code(code),
    do: code |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")

  defp hash_recovery_code(code), do: code |> normalize_recovery_code() |> Bcrypt.hash_pwd_salt()
end
