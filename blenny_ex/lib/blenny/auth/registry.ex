defmodule Blenny.AuthRegistry do
  @moduledoc """
  ETS-based registry for the singleton auth provider.

  A GenServer that creates and owns the ETS table, keeping it alive for the
  lifetime of the application. Started in the supervision tree before
  Bootstrap. Populated by the auth module's `initialize/1` callback.
  Consumed at runtime by `Blenny.Plug.FetchSession`, `Blenny.Plug.RequireUser`,
  and `Blenny.Plug.RequireRole`.
  """

  use GenServer, restart: :temporary

  @table __MODULE__

  @type provider_key ::
          nil
          | %{
              required(:module) => module(),
              required(:fetch_session) => function(),
              required(:login_route) => String.t(),
              optional(:role_check) => function()
            }

  @doc """
  Starts the AuthRegistry GenServer, which creates and owns the ETS table.
  Idempotent — safe to call multiple times.
  """
  @spec start() :: :ok
  def start do
    case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @doc """
  Starts the AuthRegistry GenServer linked to the caller (for supervision trees).
  """
  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Registers the auth provider. Raises if already registered.
  """
  @spec register(provider_key()) :: :ok
  def register(provider) do
    case :ets.lookup(@table, :provider) do
      [{_, _}] ->
        raise ArgumentError,
              "Auth provider already registered. " <>
                "Only one module with capabilities: [:auth] is allowed."

      [] ->
        :ets.insert(@table, {:provider, provider})
        :ok
    end
  end

  @doc """
  Returns the registered provider map, or `nil`.
  """
  @spec registered() :: provider_key() | nil
  def registered do
    case :ets.lookup(@table, :provider) do
      [{_, provider}] -> provider
      [] -> nil
    end
  end

  @doc """
  Stops the GenServer and deletes the ETS table (used in tests).
  """
  @spec stop() :: :ok
  def stop do
    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid)
        :ok
    end
  end

  @impl true
  def init(:ok) do
    :ets.new(@table, [:named_table, :protected, :set, :public])
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    :ok
  end
end
