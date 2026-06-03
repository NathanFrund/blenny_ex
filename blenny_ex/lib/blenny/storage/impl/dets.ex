defmodule Blenny.Storage.Impl.DETS do
  @moduledoc """
  DETS-backed user store for single-node production.

  Stores users in two DETS files (primary + username index) for O(1)
  lookups with zero external dependencies. Data persists across app
  restarts.

  ## Usage

      {:ok, pid} = Blenny.Storage.Impl.DETS.start_link(data_dir: "./data/my_app")
      {:ok, user} = Blenny.Storage.Impl.DETS.create_user(pid, %{
        username: "admin",
        password_hash: "hashed_pw",
        display_name: "Administrator",
        role: "admin"
      })

  ## File layout

      <data_dir>/users.dets       — primary store, keyed by user UUID
      <data_dir>/usernames.dets   — secondary index, keyed by username

  ## Data persistence

  Writes are flushed to disk immediately (`:dets.sync/1`) for crash
  safety. DETS limits are 2 GB per file and ~32 M rows per table —
  well beyond the needs of any single-node Blenny deployment.
  """

  @behaviour Blenny.Storage.User
  use GenServer

  # ── Public API ──────────────────────────────────────────────────────

  @impl true
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def stop(pid) do
    GenServer.stop(pid)
  end

  @impl true
  def find_by_id(pid, id) do
    GenServer.call(pid, {:find_by_id, id})
  end

  @impl true
  def find_by_username(pid, username) do
    GenServer.call(pid, {:find_by_username, username})
  end

  @impl true
  def create_user(pid, attrs) do
    GenServer.call(pid, {:create_user, attrs})
  end

  @impl true
  def update_password_hash(pid, id, new_hash) do
    GenServer.call(pid, {:update_password_hash, id, new_hash})
  end

  @impl true
  def update_avatar_key(pid, id, key) do
    GenServer.call(pid, {:update_avatar_key, id, key})
  end

  @impl true
  def delete_user(pid, id) do
    GenServer.call(pid, {:delete_user, id})
  end

  # ── GenServer callbacks ────────────────────────────────────────────

  @impl true
  def init(opts) do
    data_dir = Keyword.get(opts, :data_dir, "./data/blenny")
    File.mkdir_p!(data_dir)

    users_path = to_charlist(Path.join(data_dir, "users.dets"))
    uname_path = to_charlist(Path.join(data_dir, "usernames.dets"))

    {:ok, users_ref} = :dets.open_file(users_path, [{:type, :set}])
    {:ok, uname_ref} = :dets.open_file(uname_path, [{:type, :set}])

    {:ok, %{users_ref: users_ref, uname_ref: uname_ref}}
  end

  @impl true
  def handle_call({:find_by_id, id}, _from, state) do
    result =
      case :dets.lookup(state.users_ref, id) do
        [{^id, user}] -> user
        [] -> nil
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:find_by_username, username}, _from, state) do
    result =
      case :dets.lookup(state.uname_ref, username) do
        [{^username, id}] ->
          case :dets.lookup(state.users_ref, id) do
            [{^id, user}] -> user
            [] -> nil
          end

        [] ->
          nil
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_user, attrs}, _from, state) do
    username = attrs.username

    case :dets.lookup(state.uname_ref, username) do
      [{^username, _existing_id}] ->
        {:reply, {:error, :already_exists}, state}

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

        :dets.insert(state.users_ref, {id, user})
        :dets.insert(state.uname_ref, {username, id})
        :dets.sync(state.users_ref)
        :dets.sync(state.uname_ref)

        {:reply, {:ok, user}, state}
    end
  end

  @impl true
  def handle_call({:update_password_hash, id, new_hash}, _from, state) do
    result =
      case :dets.lookup(state.users_ref, id) do
        [{^id, user}] ->
          updated = %{user | password_hash: new_hash}
          :dets.insert(state.users_ref, {id, updated})
          :dets.sync(state.users_ref)
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_avatar_key, id, key}, _from, state) do
    result =
      case :dets.lookup(state.users_ref, id) do
        [{^id, user}] ->
          updated = %{user | avatar_key: key}
          :dets.insert(state.users_ref, {id, updated})
          :dets.sync(state.users_ref)
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_user, id}, _from, state) do
    result =
      case :dets.lookup(state.users_ref, id) do
        [{^id, user}] ->
          :dets.delete(state.users_ref, id)
          :dets.delete(state.uname_ref, user.username)
          :dets.sync(state.users_ref)
          :dets.sync(state.uname_ref)
          :ok

        [] ->
          {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    :dets.close(state.users_ref)
    :dets.close(state.uname_ref)
    :ok
  end
end
