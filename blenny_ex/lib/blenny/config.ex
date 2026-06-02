defmodule Blenny.Config do
  @moduledoc """
  Reads Blenny configuration from the host application's environment.

  All configuration lives under the `:blenny_ex` application key. Values
  can be set in any config file (config.exs, runtime.exs, etc.).

  ## Example

      config :blenny_ex,
        hub: [max_connections: 10_000, max_per_user: 100],
        transport: [idle_timeout_ms: 300_000]
  """

  @defaults [
    hub: [
      max_connections: 10_000,
      max_per_user: 100
    ],
    transport: [
      idle_timeout_ms: 300_000,
      auth_required: false
    ]
  ]

  @doc """
  Returns the configured value for a given key path, falling back to defaults.
  """
  @spec get(atom() | [atom()]) :: term()
  def get(key) when is_atom(key), do: get([key])

  def get(key_path) when is_list(key_path) do
    app_value = Application.get_env(:blenny_ex, hd(key_path))
    default = deep_get(@defaults, key_path)

    case app_value do
      nil -> default
      val when is_list(val) and is_atom(hd(key_path)) ->
        Keyword.merge(default || [], val)
      val -> val
    end
  end

  @doc """
  Returns all configuration for a given top-level key.
  """
  @spec get_all(atom()) :: Keyword.t()
  def get_all(key) when is_atom(key) do
    Application.get_env(:blenny_ex, key, [])
    |> Keyword.merge(@defaults[key] || [], fn _k, app, _default -> app end)
  end

  defp deep_get(nil, _), do: nil
  defp deep_get(_, []), do: nil
  defp deep_get(kw, [k]) when is_list(kw), do: kw[k]
  defp deep_get(kw, [k | rest]) when is_list(kw) do
    case kw[k] do
      nil -> nil
      val -> deep_get(val, rest)
    end
  end
end
