defmodule Blenny.RouterTest do
  use ExUnit.Case, async: true

  defmodule TestRouteModule do
    use Blenny.Module

    @impl true
    def name, do: "rt"

    @impl true
    def routes do
      [
        %{method: :get, path: "/public", handler: :public_action},
        {:get, "/also-public", :also_public},
        {:post, "/protected", :protected_action, [auth: true]}
      ]
    end

    @impl true
    def capabilities, do: []

    @impl true
    def subscriptions, do: []
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

    test "generates public route from map format", %{routes: routes} do
      r = Enum.find(routes, &(&1.plug_opts == :public_action))
      assert r, "expected :public_action route"
      assert r.path == "/m/public"
      assert r.plug == Blenny.RouterTest.TestRouteModule
      assert r.verb == :get
    end

    test "generates public route from tuple format", %{routes: routes} do
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
    test "normalizes map format route" do
      result = Blenny.Router.normalize_route(%{method: :get, path: "/foo", handler: :bar})
      assert result == %{method: :get, path: "/foo", handler: :bar, auth: false}
    end

    test "normalizes map format with auth: true" do
      result =
        Blenny.Router.normalize_route(%{method: :post, path: "/foo", handler: :bar, auth: true})

      assert result == %{method: :post, path: "/foo", handler: :bar, auth: true}
    end

    test "normalizes 3-tuple format" do
      result = Blenny.Router.normalize_route({:get, "/foo", :bar})
      assert result == %{method: :get, path: "/foo", handler: :bar, auth: false}
    end

    test "normalizes 4-tuple format with auth option" do
      result = Blenny.Router.normalize_route({:put, "/foo", :bar, [auth: true]})
      assert result == %{method: :put, path: "/foo", handler: :bar, auth: true}
    end

    test "raises on invalid HTTP method" do
      assert_raise ArgumentError, ~r{invalid HTTP method}, fn ->
        Blenny.Router.normalize_route({:options, "/foo", :bar})
      end
    end
  end
end
