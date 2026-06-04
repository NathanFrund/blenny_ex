defmodule Blenny.Storage.Impl.InMemory do
  @moduledoc """
  ETS-backed user store for development and testing.

  A GenServer that owns the named ETS tables. Created during the auth
  module's `initialize/1` callback or added to a supervision tree.

  ## Usage

      {:ok, pid} = Blenny.Storage.Impl.InMemory.start_link([])
      {:ok, user} = Blenny.Storage.Impl.InMemory.create_user(pid, %{
        username: "admin",
        password_hash: "hashed_pw",
        display_name: "Administrator",
        role: "admin"
      })
  """

  use GenServer, restart: :temporary

  @behaviour Blenny.Storage.User

  @table :blenny_storage_in_memory
  @index :blenny_storage_in_memory_uname

  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(_opts) do
    create_tables()
    {:ok, %{}}
  end

  @impl true
  def stop(pid) do
    if Process.alive?(pid), do: GenServer.stop(pid)
    :ok
  end

  @impl true
  def find_by_id(_pid, id) do
    case :ets.lookup(@table, id) do
      [{^id, user}] -> user
      [] -> nil
    end
  end

  @impl true
  def find_by_username(_pid, username) do
    case :ets.lookup(@index, username) do
      [{^username, id}] -> find_by_id(self(), id)
      [] -> nil
    end
  end

  @impl true
  @spec create_user(pid(), map()) :: {:ok, Blenny.Storage.User.stored_user()} | {:error, :already_exists}
  def create_user(_pid, attrs) do
    username = attrs.username

    case :ets.lookup(@index, username) do
      [{^username, _existing_id}] ->
        {:error, :already_exists}

      [] ->
        id = Blenny.Storage.UUID.generate()
        now = System.system_time(:millisecond)

        user = %{
          id: id,
          username: username,
          password_hash: attrs.password_hash,
          display_name: attrs.display_name,
          role: Map.get(attrs, :role) || "user",
          avatar_key: nil,
          created_at: now
        }

        :ets.insert(@table, {id, user})
        :ets.insert(@index, {username, id})

        {:ok, user}
    end
  end

  @impl true
  def update_password_hash(_pid, id, new_hash) do
    case :ets.lookup(@table, id) do
      [{^id, user}] ->
        updated = %{user | password_hash: new_hash}
        :ets.insert(@table, {id, updated})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def update_avatar_key(_pid, id, key) do
    case :ets.lookup(@table, id) do
      [{^id, user}] ->
        updated = %{user | avatar_key: key}
        :ets.insert(@table, {id, updated})
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @impl true
  def delete_user(_pid, id) do
    case :ets.lookup(@table, id) do
      [{^id, user}] ->
        :ets.delete(@table, id)
        :ets.delete(@index, user.username)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  defp create_tables do
    for name <- [@table, @index] do
      case :ets.info(name) do
        :undefined -> :ets.new(name, [:named_table, :protected, :set, :public])
        _ -> :ok
      end
    end
  end
end
