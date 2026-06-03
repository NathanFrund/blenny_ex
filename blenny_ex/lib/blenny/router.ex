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

  Routes tagged `auth: true` in the module's `routes/0` are automatically
  wrapped with `Blenny.Plug.RequireUser` inside a `scope "/"`.

  ## Route Format

  Modules return routes from `routes/0` as maps or tuples:

      # Map format (current)
      %{method: :get, path: "/signin", handler: :render_sign_in}
      %{method: :post, path: "/avatar", handler: :handle_avatar, auth: true}

      # Tuple format (compact)
      {:get, "/signin", :render_sign_in}
      {:post, "/avatar", :handle_avatar, [auth: true]}

  The handler must be an atom (Phoenix controller action name). The module
  itself acts as the controller — it must `use Phoenix.Controller` to provide
  the pipeline functions expected by the Phoenix router.
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

    entries =
      Enum.flat_map(modules, fn mod ->
        case Kernel.function_exported?(mod, :routes, 0) do
          true ->
            for route <- mod.routes(), do: {mod, normalize_route(route)}

          false ->
            []
        end
      end)

    {public, auth} = Enum.split_with(entries, fn {_mod, r} -> not r[:auth] end)

    quote do
      unquote(gen_routes(public, prefix))
      unquote(gen_auth_routes(auth, prefix))
    end
  end

  # ── Route normalization ─────────────────────────────────────────

  @doc false
  def normalize_route(%{method: m, path: p, handler: h} = r) do
    assert_valid_method!(m)
    %{method: m, path: p, handler: h, auth: Map.get(r, :auth, false)}
  end

  def normalize_route({method, path, handler}) do
    assert_valid_method!(method)
    %{method: method, path: path, handler: handler, auth: false}
  end

  def normalize_route({method, path, handler, opts}) when is_list(opts) do
    assert_valid_method!(method)
    %{method: method, path: path, handler: handler, auth: Keyword.get(opts, :auth, false)}
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
    Enum.map(entries, fn {mod, route} ->
      path = prefix <> route.path
      handler = route.handler
      method = route.method

      quote do
        unquote(method)(unquote(path), unquote(mod), unquote(handler))
      end
    end)
  end

  defp gen_auth_routes([], _prefix), do: []

  defp gen_auth_routes(entries, prefix) do
    inner =
      Enum.map(entries, fn {mod, route} ->
        path = prefix <> route.path
        handler = route.handler
        method = route.method

        quote do
          unquote(method)(unquote(path), unquote(mod), unquote(handler))
        end
      end)

    quote do
      scope "/" do
        pipe_through([Blenny.Plug.RequireUser])
        unquote_splicing(inner)
      end
    end
  end
end
