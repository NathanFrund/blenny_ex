defmodule Blenny.Auth.PlugTest do
  use ExUnit.Case, async: true

  setup do
    Blenny.AuthRegistry.start()

    on_exit(fn ->
      Blenny.AuthRegistry.stop()
    end)

    :ok
  end

  # ── FetchSession ───────────────────────────────────────────────

  describe "FetchSession" do
    test "sets blenny_auth when provider fetch_session returns auth struct" do
      Blenny.AuthRegistry.register(%{
        module: __MODULE__,
        fetch_session: fn _conn -> %Blenny.Auth{id: "u1", role: "admin"} end,
        login_route: "/login"
      })

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Blenny.Plug.FetchSession.call([])

      assert conn.assigns.blenny_auth == %Blenny.Auth{id: "u1", role: "admin"}
    end

    test "does not set blenny_auth when fetch_session returns nil" do
      Blenny.AuthRegistry.register(%{
        module: __MODULE__,
        fetch_session: fn _conn -> nil end,
        login_route: "/login"
      })

      conn =
        :get
        |> Plug.Test.conn("/")
        |> Blenny.Plug.FetchSession.call([])

      refute Map.has_key?(conn.assigns, :blenny_auth)
    end

    test "is no-op when no provider registered" do
      # Don't register anything — AuthRegistry is empty
      conn =
        :get
        |> Plug.Test.conn("/")
        |> Blenny.Plug.FetchSession.call([])

      refute Map.has_key?(conn.assigns, :blenny_auth)
    end
  end

  # ── RequireUser ────────────────────────────────────────────────

  describe "RequireUser" do
    test "passes through when blenny_auth is present" do
      conn =
        :get
        |> Plug.Test.conn("/protected")
        |> Plug.Conn.assign(:blenny_auth, %Blenny.Auth{id: "u1", role: "user"})
        |> Blenny.Plug.RequireUser.call([])

      assert conn.status == nil
      assert conn.halted == false
    end

    test "redirects to login route when blenny_auth is absent and provider is registered" do
      Blenny.AuthRegistry.register(%{
        module: __MODULE__,
        fetch_session: fn _conn -> nil end,
        login_route: "/custom-login"
      })

      conn =
        :get
        |> Plug.Test.conn("/protected")
        |> Blenny.Plug.RequireUser.call([])

      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/custom-login"]
      assert conn.halted == true
    end

    test "redirects to default /auth/signin when no provider registered" do
      conn =
        :get
        |> Plug.Test.conn("/protected")
        |> Blenny.Plug.RequireUser.call([])

      assert conn.status == 302
      assert Plug.Conn.get_resp_header(conn, "location") == ["/auth/signin"]
      assert conn.halted == true
    end

    test "returns 401 JSON for JSON API requests" do
      conn =
        :get
        |> Plug.Test.conn("/api/data")
        |> Plug.Conn.put_req_header("accept", "application/json")
        |> Blenny.Plug.RequireUser.call([])

      assert conn.status == 401
      assert conn.resp_body =~ "unauthorized"
      assert conn.halted == true
    end
  end

  # ── RequireRole ────────────────────────────────────────────────

  describe "RequireRole" do
    test "passes through when role matches" do
      conn =
        :get
        |> Plug.Test.conn("/admin")
        |> Plug.Conn.assign(:blenny_auth, %Blenny.Auth{id: "u1", role: "admin"})
        |> Blenny.Plug.RequireRole.call(["admin"])

      assert conn.status == nil
      assert conn.halted == false
    end

    test "passes through when role is in allowed list" do
      conn =
        :get
        |> Plug.Test.conn("/mod")
        |> Plug.Conn.assign(:blenny_auth, %Blenny.Auth{id: "u1", role: "moderator"})
        |> Blenny.Plug.RequireRole.call(["admin", "moderator"])

      assert conn.status == nil
      assert conn.halted == false
    end

    test "returns 403 when role does not match" do
      conn =
        :get
        |> Plug.Test.conn("/admin")
        |> Plug.Conn.assign(:blenny_auth, %Blenny.Auth{id: "u1", role: "user"})
        |> Blenny.Plug.RequireRole.call(["admin"])

      assert conn.status == 403
      assert conn.resp_body =~ "forbidden"
      assert conn.halted == true
    end

    test "returns 403 when no auth present" do
      conn =
        :get
        |> Plug.Test.conn("/admin")
        |> Blenny.Plug.RequireRole.call(["admin"])

      assert conn.status == 403
      assert conn.resp_body =~ "forbidden"
      assert conn.halted == true
    end

    test "accepts single atom wrapped in list" do
      conn =
        :get
        |> Plug.Test.conn("/admin")
        |> Plug.Conn.assign(:blenny_auth, %Blenny.Auth{id: "u1", role: "admin"})
        |> Blenny.Plug.RequireRole.call("admin")

      assert conn.status == nil
      assert conn.halted == false
    end
  end
end
