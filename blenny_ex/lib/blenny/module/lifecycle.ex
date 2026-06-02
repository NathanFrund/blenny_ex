defmodule Blenny.Module.Lifecycle do
  require Logger
  @moduledoc """
  Orchestrates the module lifecycle — initialize, start, and stop.

  Modules are processed in registration order. Stop is called in reverse order.
  """

  @type state :: map()

  @doc """
  Initializes all modules with the given app state.

  Calls `c:Blenny.Module.initialize/1` on each module that defines it.
  Returns `:ok` or raises on first error.
  """
  @spec initialize_all([module()], state()) :: :ok
  def initialize_all(modules, state) do
    Enum.reduce_while(modules, :ok, fn mod, _acc ->
      if function_exported?(mod, :initialize, 1) do
        case mod.initialize(state) do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, mod, reason}}
        end
      else
        {:cont, :ok}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, mod, reason} -> raise "Module #{inspect(mod)} initialize failed: #{inspect(reason)}"
    end
  end

  @doc """
  Starts all modules.

  Calls `c:Blenny.Module.start/0` on each module that defines it.
  Returns `:ok` or raises on first error.
  """
  @spec start_all([module()]) :: :ok
  def start_all(modules) do
    Enum.reduce_while(modules, :ok, fn mod, _acc ->
      if function_exported?(mod, :start, 0) do
        case mod.start() do
          :ok -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, mod, reason}}
        end
      else
        {:cont, :ok}
      end
    end)
    |> case do
      :ok -> :ok
      {:error, mod, reason} -> raise "Module #{inspect(mod)} start failed: #{inspect(reason)}"
    end
  end

  @doc """
  Stops all modules in reverse order.

  Calls `c:Blenny.Module.stop/0` on each module that defines it.
  Errors are logged but do not halt shutdown.
  """
  @spec stop_all([module()]) :: :ok
  def stop_all(modules) do
    modules
    |> Enum.reverse()
    |> Enum.each(fn mod ->
      if function_exported?(mod, :stop, 0) do
        case mod.stop() do
          :ok -> :ok
          {:error, reason} ->
            Logger.warning("Module #{inspect(mod)} stop error: #{inspect(reason)}")
        end
      end
    end)

    :ok
  end
end
