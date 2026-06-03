defmodule Blenny.Config do
  @moduledoc """
  Reads Blenny configuration from the host application's environment.

  All configuration lives under the `:blenny_ex` application key. Values
  can be set in any config file (config.exs, runtime.exs, etc.).

  ## Example

      config :blenny_ex,
        pub_sub: MyApp.PubSub,
        hub: [max_connections: 10_000, max_per_user: 100],
        transport: [idle_timeout_ms: 300_000]

  ## Validation

  Configuration is validated during `Blenny.Bootstrap.boot/0` using
  `NimbleOptions`. Invalid config raises a descriptive error at boot.
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

  @schema [
    pub_sub: [
      type: :atom,
      required: true,
      doc: "Your Phoenix app's PubSub module (e.g. MyApp.PubSub)"
    ],
    modules: [
      type: {:list, :atom},
      default: [],
      doc: "Explicit module registration override (optional)"
    ],
    hub: [
      type: :keyword_list,
      default: [],
      keys: [
        max_connections: [
          type: :pos_integer,
          default: 10_000,
          doc: "Maximum concurrent connections system-wide"
        ],
        max_per_user: [
          type: :pos_integer,
          default: 100,
          doc: "Maximum connections per dedup key (user_id for auth, conn.id for anonymous)"
        ]
      ],
      doc: "Hub connection limit settings"
    ],
    transport: [
      type: :keyword_list,
      default: [],
      keys: [
        idle_timeout_ms: [
          type: :pos_integer,
          default: 300_000,
          doc: "Transport idle timeout in milliseconds"
        ],
        auth_required: [
          type: :boolean,
          default: false,
          doc: "Whether authentication is required for all connections"
        ]
      ],
      doc: "Transport-level settings"
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
      nil ->
        default

      val when is_list(val) and is_atom(hd(key_path)) ->
        Keyword.merge(default || [], val)

      val ->
        val
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

  # Internal keys set by @before_compile hooks — excluded from user-facing validation
  @internal_keys [:module_routes, :registered_modules]

  @doc """
  Validates the application's `:blenny_ex` config against the NimbleOptions
  schema. Raises on invalid config.

  Internal framework keys (set by `@before_compile` hooks) are excluded from
  validation automatically.
  """
  @spec validate!() :: :ok
  def validate! do
    config =
      Application.get_all_env(:blenny_ex)
      |> Keyword.drop(@internal_keys)

    NimbleOptions.validate!(config, @schema)
    :ok
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
