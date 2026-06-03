defmodule Blenny.Connection.Registry do
  @moduledoc """
  ETS-backed registry for tracking active Blenny connections.

  Provides O(1) lookup by connection ID, per-user lookups, and dedup-key
  lookups for enforcing at-most-one connection per `{user_id, conn_type}`.
  """

  @table_name :blenny_connections
  @dedup_index :blenny_connections_by_dedup
  @user_index :blenny_connections_by_user

  @doc """
  Creates the ETS tables. Called during boot.
  """
  @spec start_link() :: {:ok, :ets.tid()}
  def start_link do
    tid = :ets.new(@table_name, [:ordered_set, :public, :named_table, write_concurrency: true])

    :ets.new(@dedup_index, [:set, :public, :named_table, write_concurrency: true])
    :ets.new(@user_index, [:bag, :public, :named_table, write_concurrency: true])

    {:ok, tid}
  end

  @doc """
  Registers a connection into the ETS tables.

  Returns `{:ok, conn}` on success.
  """
  @spec register(Blenny.Connection.t()) :: {:ok, Blenny.Connection.t()}
  def register(%Blenny.Connection{} = conn) do
    true = :ets.insert(@table_name, {conn.id, conn})
    true = :ets.insert(@dedup_index, {{dedup_key(conn), conn.conn_type}, conn.id})

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
        true = :ets.delete(@dedup_index, {dedup_key(conn), conn.conn_type})

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
  Looks up an existing connection by dedup key and conn type.

  The dedup key is `user_id` if present, or the connection's id as fallback.
  Since the dedup index is a `:set`, each `{dedup_key, conn_type}` has at
  most one entry. Returns `nil` if no connection exists.
  """
  @spec lookup_by_dedup_key(String.t(), atom()) :: Blenny.Connection.t() | nil
  def lookup_by_dedup_key(dedup_key, conn_type) do
    case :ets.lookup(@dedup_index, {dedup_key, conn_type}) do
      [{{^dedup_key, ^conn_type}, conn_id}] -> lookup(conn_id)
      [] -> nil
    end
  end

  @doc """
  Looks up all connections for a user ID.
  """
  @spec lookup_by_user(String.t()) :: [Blenny.Connection.t()]
  def lookup_by_user(user_id) when is_binary(user_id) do
    @user_index
    |> :ets.lookup(user_id)
    |> Enum.map(fn {^user_id, conn_id} -> lookup(conn_id) end)
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
    :ets.delete_all_objects(@dedup_index)
    :ets.delete_all_objects(@user_index)
    :ok
  end

  defp dedup_key(%{user_id: user_id}) when is_binary(user_id), do: user_id
  defp dedup_key(%{id: id}), do: id
end
