defmodule Blenny.Connection.Registry do
  @moduledoc """
  ETS-backed registry for tracking active Blenny connections.

  Provides O(1) lookup by connection ID and indexed lookups by session ID
  and user ID. Enforces session-level exclusivity — at most one connection
  per session_id.

  ## Session Dedup

  When a client connects with a session_id that already has a connection,
  the registry can replace the existing connection (closing the old one)
  or reject the new one, depending on `replace_existing?`.
  """

  @table_name :blenny_connections
  @session_index :blenny_connections_by_session
  @user_index :blenny_connections_by_user

  @doc """
  Creates the ETS tables. Called during boot.
  """
  @spec start_link() :: {:ok, :ets.tid()}
  def start_link do
    tid = :ets.new(@table_name, [:ordered_set, :public, :named_table, write_concurrency: true])

    :ets.new(@session_index, [:bag, :public, :named_table, write_concurrency: true])
    :ets.new(@user_index, [:bag, :public, :named_table, write_concurrency: true])

    {:ok, tid}
  end

  @doc """
  Registers a connection.

  Returns `{:ok, conn}` on success.

  If `:replace_existing` is `true` and the session already has a connection,
  the old connection is removed and the new one takes its place.
  Returns `{:error, :session_already_connected}` if `:replace_existing` is
  `false` and the session already has a connection.
  """
  @spec register(Blenny.Connection.t(), keyword()) ::
          {:ok, Blenny.Connection.t()} | {:error, :session_already_connected}
  def register(%Blenny.Connection{} = conn, opts \\ []) do
    replace? = Keyword.get(opts, :replace_existing, true)

    case lookup_by_session(conn.session_id) do
      [existing] when replace? ->
        unregister(existing.id)

      [_existing] ->
        {:error, :session_already_connected}

      [] ->
        :ok
    end

    true = :ets.insert(@table_name, {conn.id, conn})

    true = :ets.insert(@session_index, {conn.session_id, conn.id})
    if conn.user_id do
      true = :ets.insert(@user_index, {conn.user_id, conn.id})
    end

    {:ok, conn}
  end

  @doc """
  Removes a connection by ID. Returns the removed connection or `nil`.
  """
  @spec unregister(String.t()) :: Blenny.Connection.t() | nil
  def unregister(conn_id) when is_binary(conn_id) do
    case lookup(conn_id) do
      nil ->
        nil

      conn ->
        true = :ets.delete(@table_name, conn_id)
        true = :ets.delete_object(@session_index, {conn.session_id, conn_id})

        if conn.user_id do
          true = :ets.delete_object(@user_index, {conn.user_id, conn_id})
        end

        conn
    end
  end

  @doc """
  Looks up a connection by ID.
  """
  @spec lookup(String.t()) :: Blenny.Connection.t() | nil
  def lookup(conn_id) when is_binary(conn_id) do
    case :ets.lookup(@table_name, conn_id) do
      [{^conn_id, conn}] -> conn
      [] -> nil
    end
  end

  @doc """
  Looks up connections for a user ID.
  """
  @spec lookup_by_user(String.t()) :: [Blenny.Connection.t()]
  def lookup_by_user(user_id) when is_binary(user_id) do
    @user_index
    |> :ets.lookup(user_id)
    |> Enum.map(fn {^user_id, conn_id} -> lookup(conn_id) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Looks up the connection for a session ID.

  Returns `[conn]` or `[]`. Session-level dedup ensures at most one connection.
  """
  @spec lookup_by_session(String.t()) :: [Blenny.Connection.t()]
  def lookup_by_session(session_id) when is_binary(session_id) do
    @session_index
    |> :ets.lookup(session_id)
    |> Enum.map(fn {^session_id, conn_id} -> lookup(conn_id) end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Returns all connections in the registry.
  """
  @spec all() :: [Blenny.Connection.t()]
  def all do
    @table_name
    |> :ets.match({:"$1", :"$2"})
    |> Enum.map(fn [_, conn] -> conn end)
  end

  @doc """
  Returns the count of active connections.
  """
  @spec count() :: non_neg_integer()
  def count do
    :ets.info(@table_name, :size)
  end

  @doc """
  Clears all connections from the registry.
  """
  @spec clear() :: :ok
  def clear do
    :ets.delete_all_objects(@table_name)
    :ets.delete_all_objects(@session_index)
    :ets.delete_all_objects(@user_index)
    :ok
  end
end
