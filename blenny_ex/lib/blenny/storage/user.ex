defmodule Blenny.Storage.User do
  @moduledoc """
  Behaviour for user stores — mirrors the TypeScript `UserStore` interface.

  A stored user is a map with atom keys matching the `t:stored_user/0` type.
  The `create_user/1` callback generates `:id` (UUIDv4) and `:created_at`
  (Unix milliseconds) automatically.
  """

  @typedoc """
  A persisted user record.

  All keys are atoms for predictable pattern matching across
  memory and disk implementations.

    * `:id` — UUIDv4 string, generated on creation
    * `:username` — unique login name
    * `:password_hash` — BCrypt or PBKDF2 hash
    * `:display_name` — human-readable name
    * `:role` — role string (e.g. `"user"`, `"admin"`)
    * `:avatar_key` — blob store key (`nil` until first upload)
    * `:created_at` — Unix milliseconds
  """
  @type stored_user :: %{
          required(:id) => String.t(),
          required(:username) => String.t(),
          required(:password_hash) => String.t(),
          required(:display_name) => String.t(),
          required(:role) => String.t(),
          optional(:avatar_key) => String.t() | nil,
          required(:created_at) => integer()
        }

  @doc "Finds a user by UUID."
  @callback find_by_id(pid(), id :: String.t()) :: stored_user() | nil

  @doc "Finds a user by username (uses secondary index)."
  @callback find_by_username(pid(), username :: String.t()) :: stored_user() | nil

  @doc "Creates a new user. Generates `:id` and `:created_at` automatically."
  @callback create_user(pid(), attrs :: map()) :: {:ok, stored_user()} | {:error, term()}

  @doc "Updates the password hash for a user."
  @callback update_password_hash(pid(), id :: String.t(), new_hash :: String.t()) ::
              :ok | {:error, term()}

  @doc "Sets the avatar key for a user."
  @callback update_avatar_key(pid(), id :: String.t(), key :: String.t()) ::
              :ok | {:error, term()}

  @doc "Deletes a user and its username index."
  @callback delete_user(pid(), id :: String.t()) :: :ok | {:error, term()}

  @doc "Starts the store as a GenServer (for supervised lifecycle)."
  @callback start_link(opts :: keyword()) :: GenServer.on_start()

  @doc "Stops the store gracefully."
  @callback stop(pid()) :: :ok
end
