defmodule Blenny.Router do
  @moduledoc """
  Macro for mounting Blenny module routes into the host application's router.

  ## Usage

  In your `router.ex`:

      defmodule MyAppWeb.Router do
        use MyAppWeb, :router
        import Blenny.Router

        pipeline :browser do
          plug :accepts, ["html"]
          plug :fetch_session
          plug Blenny.Plug.FetchSession
        end

        scope "/" do
          pipe_through :browser

          blenny_modules("/m")
        end
      end

  Routes tagged `auth: true` are automatically wrapped with
  `Blenny.Plug.RequireUser` inside a nested `scope "/"`.

  ## Route Format

  Modules declare routes via `@blenny_routes` module attribute with a
  type-tagged tuple as the first element:

      # Standard HTTP
      {:http, :get, "/signin", __MODULE__, :render_sign_in}
      {:http, :post, "/avatar", __MODULE__, :handle_avatar, [auth: true]}

      # LiveView
      {:live, "/dashboard", MyAppWeb.DashboardLive}
      {:live, "/dashboard", MyAppWeb.DashboardLive, :index}
  """

  @http_methods [:get, :post, :put, :patch, :delete]

  @doc """
  Mounts Blenny module routes under the given path prefix.

  ## Options

    * `:modules` — explicit module list for testing. Defaults to
      `Blenny.Module.Loader.modules/0` at compile time.
  """
  defmacro blenny_modules(prefix, opts \\ []) do
    raw = opts[:modules] || Blenny.Module.Loader.modules()

    modules =
      Enum.map(raw, fn
        {:__aliases__, _, _} = alias -> Macro.expand(alias, __CALLER__)
        mod when is_atom(mod) -> mod
      end)

    route_registry = Application.get_env(:blenny_ex, :module_routes, [])

    entries =
      Enum.flat_map(modules, fn mod ->
        case Enum.find_value(route_registry, fn
               {m, rs} when m == mod -> rs
               _ -> nil
             end) do
          nil -> []
          routes -> for route <- routes, do: normalize_route(route)
        end
      end)

    {public, auth} = Enum.split_with(entries, fn r -> not r[:auth] end)

    quote do
      unquote(gen_routes(public, prefix))
      unquote(gen_auth_routes(auth, prefix))
    end
  end

  # ── Route normalization ─────────────────────────────────────────

  @doc false
  def normalize_route({:http, method, path, plug, action, opts}) when is_list(opts) do
    assert_valid_method!(method)

    %{
      type: :http,
      method: method,
      path: path,
      plug: plug,
      opts: action,
      auth: Keyword.has_key?(opts, :auth)
    }
  end

  def normalize_route({:http, method, path, plug, opts}) when is_list(opts) do
    assert_valid_method!(method)

    %{
      type: :http,
      method: method,
      path: path,
      plug: plug,
      opts: opts,
      auth: Keyword.has_key?(opts, :auth)
    }
  end

  def normalize_route({:http, method, path, plug, action}) do
    assert_valid_method!(method)
    %{type: :http, method: method, path: path, plug: plug, opts: action, auth: false}
  end

  def normalize_route({:live, path, live_view, opts}) when is_list(opts) do
    auth = Keyword.has_key?(opts, :auth)
    clean = Keyword.delete(opts, :auth)

    %{
      type: :live,
      path: path,
      plug: live_view,
      opts: if(clean == [], do: nil, else: clean),
      auth: auth
    }
  end

  def normalize_route({:live, path, live_view, action}) do
    %{type: :live, path: path, plug: live_view, opts: action, auth: false}
  end

  def normalize_route({:live, path, live_view}) do
    %{type: :live, path: path, plug: live_view, opts: nil, auth: false}
  end

  defp assert_valid_method!(method) when method in @http_methods, do: :ok

  defp assert_valid_method!(method) do
    raise ArgumentError,
          "invalid HTTP method #{inspect(method)} in Blenny module route. " <>
            "Expected one of: #{inspect(@http_methods)}"
  end

  # ── Code generation ─────────────────────────────────────────────

  defp gen_routes([], _prefix), do: []

  defp gen_routes(entries, prefix) do
    Enum.map(entries, &gen_route(&1, prefix))
  end

  defp gen_auth_routes([], _prefix), do: []

  defp gen_auth_routes(entries, prefix) do
    inner = Enum.map(entries, &gen_route(&1, prefix))

    quote do
      scope "/" do
        pipe_through([Blenny.Plug.RequireUser])
        unquote_splicing(inner)
      end
    end
  end

  defp gen_route(%{type: :http, method: method, path: path, plug: plug, opts: opts}, prefix) do
    p = prefix <> path

    quote do
      unquote(method)(unquote(p), unquote(plug), unquote(opts))
    end
  end

  defp gen_route(%{type: :live, path: path, plug: plug, opts: nil}, prefix) do
    p = prefix <> path

    quote do
      live(unquote(p), unquote(plug))
    end
  end

  defp gen_route(%{type: :live, path: path, plug: plug, opts: opts}, prefix) do
    p = prefix <> path

    quote do
      live(unquote(p), unquote(plug), unquote(opts))
    end
  end
end
