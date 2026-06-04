defmodule Blenny.Module.Lifecycle do
  require Logger

  @moduledoc """
  Orchestrates the module lifecycle — initialize, supervised start,
  and subscription wiring.

  Modules are processed in registration order. The DynamicSupervisor handles
  stop/shutdown naturally.
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
      :ok ->
        :ok

      {:error, mod, reason} ->
        raise "Module #{inspect(mod)} initialize failed: #{inspect(reason)}"
    end
  end

  @doc """
  Starts supervised modules under the given DynamicSupervisor.

  Calls `c:Blenny.Module.child_spec/1` on each module. If it returns a child
  spec (rather than `:skip`), starts it under the supervisor.
  """
  @spec start_supervised([module()], atom()) :: :ok
  def start_supervised(modules, supervisor) do
    Enum.each(modules, fn mod ->
      case mod.child_spec([]) do
        :skip ->
          :ok

        child_spec ->
          case DynamicSupervisor.start_child(supervisor, child_spec) do
            {:ok, _pid} ->
              :ok

            {:ok, _pid, _info} ->
              :ok

            {:error, {:already_started, _pid}} ->
              :ok

            {:error, reason} ->
              raise "Module #{inspect(mod)} failed to start under #{inspect(supervisor)}: #{inspect(reason)}"
          end
      end
    end)
  end

  @doc """
  Wires PubSub subscriptions for modules that define `subscriptions/0`.

  For each module that exports `subscriptions/0` and returns a non-empty
  list of topic strings, looks up the module's background process via
  `Blenny.ModuleRegistry` and subscribes it to each topic.

  Declarative modules (no background process, or subscriptions returning
  `[]`) are silently skipped.
  """
  @spec wire_subscriptions([module()]) :: :ok
  def wire_subscriptions(modules) do
    Enum.each(modules, fn mod ->
      if function_exported?(mod, :subscriptions, 0) do
        topics = mod.subscriptions()

        if topics != [] do
          case Registry.lookup(Blenny.ModuleRegistry, {:module, mod}) do
            [{pid, _}] ->
              send(pid, {:blenny_subscribe, topics})

              Logger.info(
                "Sent subscribe signal to #{inspect(mod)} for #{length(topics)} topic(s)"
              )

            [] ->
              :ok
          end
        end
      end
    end)

    :ok
  end
end
