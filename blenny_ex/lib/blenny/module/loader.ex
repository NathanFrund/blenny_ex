defmodule Blenny.Module.Loader do
  @moduledoc """
  Discovers Blenny modules at compile time by scanning all loaded modules
  that implement the `Blenny.Module` behaviour.

  Modules using `use Blenny.Module` are automatically registered via a
  `@before_compile` hook that stores them in the module attribute
  `@blenny_registered_modules`. The loader collects these at runtime.

  ## Manual Registration

  If auto-discovery doesn't work for your project (e.g., modules in
  non-standard paths), you can also register modules explicitly:

      config :blenny_ex, modules: [MyApp.Blenny.Dashboard, MyApp.Blenny.Chat]
  """

  @doc """
  Returns all discovered Blenny modules.
  """
  @spec modules() :: [module()]
  def modules do
    configured = Application.get_env(:blenny_ex, :modules, [])
    discovered = discover_modules()
    Enum.uniq(configured ++ discovered)
  end

  @doc """
  Validates modules, checking for capability conflicts, missing callbacks, etc.
  Returns `:ok` or raises with a descriptive error.
  """
  @spec validate!([module()]) :: :ok
  def validate!(modules) do
    check_capability_conflicts!(modules)
    :ok
  end

  defp discover_modules do
    registered = Application.get_env(:blenny_ex, :registered_modules, [])

    loaded =
      blenny_candidates()
      |> Enum.filter(&implements_blenny?/1)

    (registered ++ loaded) |> Enum.uniq() |> Enum.filter(&Code.ensure_loaded?/1)
  end

  defp blenny_candidates do
    # Scan all loaded modules plus modules from applications' module lists.
    # This ensures modules compiled but not yet referenced are discovered.
    loaded = :code.all_loaded() |> Enum.map(fn {m, _} -> m end)

    app_mods =
      :application.loaded_applications()
      |> Enum.flat_map(fn {app, _desc, _vsn} ->
        case :application.get_key(app, :modules) do
          {:ok, mods} -> mods
          :undefined -> []
        end
      end)

    Enum.uniq(loaded ++ app_mods)
  end

  defp implements_blenny?(mod) do
    Code.ensure_loaded(mod)
    mod_behaviours = mod.__info__(:attributes)[:behaviour] || []
    Blenny.Module in List.wrap(mod_behaviours)
  rescue
    _ -> false
  end

  defp check_capability_conflicts!(modules) do
    all_caps =
      Enum.flat_map(modules, fn mod ->
        caps = mod.capabilities()
        Enum.map(caps, fn cap -> {cap, mod} end)
      end)

    conflicts =
      all_caps
      |> Enum.group_by(fn {cap, _mod} -> cap end, fn {_cap, mod} -> mod end)
      |> Enum.filter(fn {_cap, mods} -> length(mods) > 1 end)

    case conflicts do
      [] ->
        :ok

      conflicts ->
        messages =
          Enum.map(conflicts, fn {cap, mods} ->
            names = Enum.map_join(mods, ", ", &inspect/1)
            "capability \"#{cap}\" claimed by #{names}"
          end)

        raise ArgumentError, """
        Capability conflicts detected between Blenny modules:

        #{Enum.join(messages, "\n")}

        Each capability can only be claimed by one module.
        """
    end
  end
end
