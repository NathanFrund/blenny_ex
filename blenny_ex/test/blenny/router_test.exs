defmodule Blenny.RouterTest do
  use ExUnit.Case, async: true

  defmodule TestRouteModule do
    use Blenny.Module

    @blenny_routes {:http, :get, "/public", __MODULE__, :public_action}
    @blenny_routes {:http, :get, "/also-public", __MODULE__, :also_public}
    @blenny_routes {:http, :post, "/protected", __MODULE__, :protected_action, [auth: true]}

    @impl true
    def name, do: "rt"

    @impl true
    def routes, do: @blenny_routes

    @impl true
    def capabilities, do: []

    @impl true
    def subscriptions, do: []

    def init(_opts), do: {:ok, nil}
  end

  defmodule TestRouter do
    use Phoenix.Router
    import Blenny.Router

    blenny_modules("/m", modules: [Blenny.RouterTest.TestRouteModule])
  end

  setup do
    routes = TestRouter.__routes__()
    {:ok, routes: routes}
  end

  describe "blenny_modules/1 macro" do
    test "generates 3 routes", %{routes: routes} do
      assert length(routes) == 3
    end

    test "generates public route with :http tuple", %{routes: routes} do
      r = Enum.find(routes, &(&1.plug_opts == :public_action))
      assert r, "expected :public_action route"
      assert r.path == "/m/public"
      assert r.plug == Blenny.RouterTest.TestRouteModule
      assert r.verb == :get
    end

    test "generates second public route", %{routes: routes} do
      r = Enum.find(routes, &(&1.plug_opts == :also_public))
      assert r, "expected :also_public route"
      assert r.path == "/m/also-public"
      assert r.plug == Blenny.RouterTest.TestRouteModule
      assert r.verb == :get
    end

    test "generates auth-protected route with auth: true", %{routes: routes} do
      r = Enum.find(routes, &(&1.plug_opts == :protected_action))
      assert r, "expected :protected_action route"
      assert r.path == "/m/protected"
      assert r.plug == Blenny.RouterTest.TestRouteModule
      assert r.verb == :post
    end
  end

  describe "route normalization" do
    test "normalizes 5-tuple http route" do
      result = Blenny.Router.normalize_route({:http, :get, "/foo", MyPlug, :bar})

      assert result == %{
               type: :http,
               method: :get,
               path: "/foo",
               plug: MyPlug,
               opts: :bar,
               auth: false
             }
    end

    test "normalizes 6-tuple http route with auth" do
      result = Blenny.Router.normalize_route({:http, :post, "/foo", MyPlug, :bar, [auth: true]})

      assert result == %{
               type: :http,
               method: :post,
               path: "/foo",
               plug: MyPlug,
               opts: :bar,
               auth: true
             }
    end

    test "normalizes 3-tuple live route" do
      result = Blenny.Router.normalize_route({:live, "/dashboard", MyLive})
      assert result == %{type: :live, path: "/dashboard", plug: MyLive, opts: nil, auth: false}
    end

    test "normalizes 4-tuple live route with action" do
      result = Blenny.Router.normalize_route({:live, "/dashboard", MyLive, :index})
      assert result == %{type: :live, path: "/dashboard", plug: MyLive, opts: :index, auth: false}
    end

    test "normalizes 4-tuple live route with auth opts" do
      result = Blenny.Router.normalize_route({:live, "/admin", AdminLive, [auth: true]})
      assert result == %{type: :live, path: "/admin", plug: AdminLive, opts: nil, auth: true}
    end

    test "raises on invalid HTTP method" do
      assert_raise ArgumentError, ~r{invalid HTTP method}, fn ->
        Blenny.Router.normalize_route({:http, :options, "/foo", MyPlug, :bar})
      end
    end
  end
end
