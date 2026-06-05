defmodule SurrealDB do
  @moduledoc """
  Public API for the SurrealDB Elixir client.

  Provides a thin layer over the WebSocket connection process. All functions
  take a connection PID as the first argument.

  ## Starting a connection

      opts = [
        hostname: "localhost",
        port: 8000,
        username: "root",
        password: "root",
        namespace: "test",
        database: "test"
      ]

      {:ok, pid} = SurrealDB.start_link(opts)
      SurrealDB.query(pid, "SELECT * FROM user")
  """

  @doc "Starts a connection without linking."
  @spec start(keyword()) :: {:ok, pid} | {:error, term()}
  def start(opts \\ []) do
    SurrealDB.Connection.start(opts)
  end

  @doc "Starts a connection linked to the caller."
  @spec start_link(keyword()) :: {:ok, pid} | {:error, term()}
  def start_link(opts \\ []) do
    SurrealDB.Connection.start_link(opts)
  end

  @doc "Returns a child spec for use in supervision trees."
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {SurrealDB.Connection, :start_link, [opts]},
      type: :worker,
      restart: :transient,
      shutdown: 5_000
    }
  end

  @doc "Executes a SurrealQL query."
  @spec query(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate query(pid, sql, vars \\ %{}), to: SurrealDB.Connection

  @doc "Creates a record in a table."
  @spec create(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate create(pid, thing, data \\ %{}), to: SurrealDB.Connection

  @doc "Selects records from a table or thing."
  @spec select(pid(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate select(pid, thing), to: SurrealDB.Connection

  @doc "Updates a record."
  @spec update(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate update(pid, thing, data), to: SurrealDB.Connection

  @doc "Merges data into a record."
  @spec merge(pid(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate merge(pid, thing, data), to: SurrealDB.Connection

  @doc "Deletes a record."
  @spec delete(pid(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate delete(pid, thing), to: SurrealDB.Connection

  @doc "Signs in with credentials."
  @spec signin(pid(), map()) :: {:ok, map()} | {:error, term()}
  defdelegate signin(pid, payload), to: SurrealDB.Connection

  @doc "Registers a live query with callback."
  @spec live_query(pid(), String.t(), map(), function()) :: {:ok, map()} | {:error, term()}
  defdelegate live_query(pid, sql, vars \\ %{}, callback), to: SurrealDB.Connection

  @doc "Kills an active live query."
  @spec kill(pid(), String.t()) :: {:ok, map()} | {:error, term()}
  defdelegate kill(pid, query_uuid), to: SurrealDB.Connection

  @doc "Pings the server."
  @spec ping(pid()) :: {:ok, map()} | {:error, term()}
  defdelegate ping(pid), to: SurrealDB.Connection

  @doc "Returns info about the current user."
  @spec info(pid()) :: {:ok, map()} | {:error, term()}
  defdelegate info(pid), to: SurrealDB.Connection
end
