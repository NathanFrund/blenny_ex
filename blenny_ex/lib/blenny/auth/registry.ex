defmodule Blenny.AuthRegistry do
  @moduledoc """
  ETS-based registry for the singleton auth provider.

  Created during `Blenny.Bootstrap.boot/0` and populated by the
  auth module's `initialize/1`. Consumed at runtime by
  `Blenny.Plug.FetchSession`, `Blenny.Plug.RequireUser`, and
  `Blenny.Plug.RequireRole`.
  """

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
  Creates the ETS table. Called once during boot.
  """
  @spec start() :: :ok
  def start do
    case :ets.info(@table) do
      :undefined -> :ets.new(@table, [:named_table, :protected, :set, :public])
      _ -> :ok
    end
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
  Clears the registry (used in tests).
  """
  @spec stop() :: :ok
  def stop do
    case :ets.info(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table)
    end
  end
end
