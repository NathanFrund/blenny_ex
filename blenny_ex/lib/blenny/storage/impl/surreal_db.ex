defmodule Blenny.Storage.Impl.SurrealDB do
  @moduledoc """
  SurrealDB-backed user store for Blenny.

  Stores users in a SurrealDB `user` table. The SurrealDB connection is
  managed externally (started in the auth module's `initialize/1` or added
  to the supervision tree) and passed via `start_link(connection: pid)`.

  ## Usage

      {:ok, conn} = SurrealDB.start_link(...)
      {:ok, pid} = Blenny.Storage.Impl.SurrealDB.start_link(connection: conn)
      {:ok, user} = Blenny.Storage.Impl.SurrealDB.create_user(pid, %{
        username: "admin",
        password_hash: "hashed_pw",
        display_name: "Administrator",
        role: "admin"
      })

  ## Table schema

  Creates a `user` table on init with the following schema:

      DEFINE TABLE user;
      DEFINE FIELD username ON TABLE user TYPE string;
      DEFINE FIELD password_hash ON TABLE user TYPE string;
      DEFINE FIELD display_name ON TABLE user TYPE string;
      DEFINE FIELD role ON TABLE user TYPE string;
      DEFINE FIELD avatar_key ON TABLE user TYPE string;
      DEFINE FIELD created_at ON TABLE user TYPE number;
      DEFINE INDEX idx_username ON TABLE user COLUMNS username UNIQUE;
  """

  require Logger

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
    conn = Keyword.fetch!(opts, :connection)

    schema = [
      "DEFINE TABLE IF NOT EXISTS user",
      "DEFINE FIELD IF NOT EXISTS username ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS password_hash ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS display_name ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS role ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS avatar_key ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS created_at ON TABLE user TYPE number",
      "DEFINE INDEX IF NOT EXISTS idx_username ON TABLE user COLUMNS username UNIQUE"
    ]

    Enum.each(schema, fn stmt ->
      case SurrealDB.query(conn, stmt) do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("[SurrealDB.Store] Schema setup warning: #{inspect(reason)}")
      end
    end)

    {:ok, %{conn: conn}}
  end

  @impl true
  def handle_call({:find_by_id, id}, _from, state) do
    result =
      case SurrealDB.query(state.conn, "SELECT * FROM user WHERE uuid = $id", %{"id" => id}) do
        {:ok, %{"result" => [%{"result" => [user | _]}]}} -> map_user(user)
        {:ok, %{"result" => [%{"result" => []}]}} -> nil
        _ -> nil
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:find_by_username, username}, _from, state) do
    result =
      case SurrealDB.query(state.conn, "SELECT * FROM user WHERE username = $username", %{"username" => username}) do
        {:ok, %{"result" => [%{"result" => [user | _]}]}} -> map_user(user)
        {:ok, %{"result" => [%{"result" => []}]}} -> nil
        _ -> nil
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:create_user, attrs}, _from, state) do
    id = Blenny.Storage.UUID.generate()
    now = System.system_time(:millisecond)

    user_data = %{
      "uuid" => id,
      "username" => attrs.username,
      "password_hash" => attrs.password_hash,
      "display_name" => attrs.display_name,
      "role" => Map.get(attrs, :role, "user"),
      "avatar_key" => nil,
      "created_at" => now
    }

    result =
      case SurrealDB.query(state.conn, """
      CREATE user CONTENT $data
      """, %{"data" => user_data}) do
        {:ok, %{"result" => [%{"result" => [created]}]}} ->
          {:ok, map_user(created)}

        {:ok, %{"result" => [%{"status" => "ERR", "result" => error_msg}]}} ->
          {:error, error_msg}

        other ->
          {:error, other}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_password_hash, id, new_hash}, _from, state) do
    result =
      case SurrealDB.query(state.conn, "UPDATE user SET password_hash = $hash WHERE uuid = $id", %{"id" => id, "hash" => new_hash}) do
        {:ok, %{"result" => [%{"result" => [_updated]}]}} -> :ok
        {:ok, %{"result" => [%{"result" => []}]}} -> {:error, :not_found}
        _ -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:update_avatar_key, id, key}, _from, state) do
    result =
      case SurrealDB.query(state.conn, "UPDATE user SET avatar_key = $key WHERE uuid = $id", %{"id" => id, "key" => key}) do
        {:ok, %{"result" => [%{"result" => [_updated]}]}} -> :ok
        {:ok, %{"result" => [%{"result" => []}]}} -> {:error, :not_found}
        _ -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_user, id}, _from, state) do
    result =
      case SurrealDB.query(state.conn, "DELETE user WHERE uuid = $id", %{"id" => id}) do
        {:ok, %{"result" => [%{"result" => [_deleted]}]}} -> :ok
        {:ok, %{"result" => [%{"result" => []}]}} -> {:error, :not_found}
        _ -> {:error, :not_found}
      end

    {:reply, result, state}
  end

  # ── Private helpers ────────────────────────────────────────────────

  defp map_user(surreal_user) do
    %{
      id: surreal_user["uuid"],
      username: surreal_user["username"],
      password_hash: surreal_user["password_hash"],
      display_name: surreal_user["display_name"],
      role: surreal_user["role"] || "user",
      avatar_key: surreal_user["avatar_key"],
      created_at: surreal_user["created_at"]
    }
  end
end
