defmodule Blenny.Plug.FetchSession do
  @moduledoc """
  Reads the authenticated user from the registered auth provider.

  Placed in the host application's browser pipeline. Delegates to
  the auth module's `fetch_session` function registered in
  `Blenny.AuthRegistry`. Sets `conn.assigns.blenny_auth` on success.
  """

  import Plug.Conn

  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case Blenny.AuthRegistry.registered() do
      nil ->
        conn

      provider ->
        case provider.fetch_session.(conn) do
          %Blenny.Auth{} = auth ->
            assign(conn, :blenny_auth, auth)

          _ ->
            conn
        end
    end
  end
end

defmodule Blenny.Plug.RequireUser do
  @moduledoc """
  Redirects unauthenticated requests to the auth provider's login route.

  Used automatically by `blenny_modules/1` for routes tagged `auth: true`.
  For API/JSON requests with an appropriate Accept header, returns a 401
  JSON body instead.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case conn.assigns[:blenny_auth] do
      %Blenny.Auth{} ->
        conn

      _ ->
        provider = Blenny.AuthRegistry.registered()
        login_route = (provider && provider.login_route) || "/auth/signin"

        if json_request?(conn) do
          conn
          |> put_resp_content_type("application/json")
          |> send_resp(401, ~s|{"error":"unauthorized","message":"Authentication required"}|)
          |> halt()
        else
          conn
          |> redirect(to: login_route)
          |> halt()
        end
    end
  end

  defp json_request?(conn) do
    accept = Plug.Conn.get_req_header(conn, "accept") |> List.first() || ""
    String.contains?(accept, "application/json") && !String.contains?(accept, "text/html")
  end
end

defmodule Blenny.Plug.RequireRole do
  @moduledoc """
  Checks the authenticated user's role against an allowed list.

  Use in a Phoenix pipeline or per-route:

      plug Blenny.Plug.RequireRole, :admin
      plug Blenny.Plug.RequireRole, [:admin, :moderator]

  Returns 403 for insufficient privileges.
  """

  import Plug.Conn

  def init(opts), do: List.wrap(opts)

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, raw) do
    allowed = List.wrap(raw)

    case conn.assigns[:blenny_auth] do
      %Blenny.Auth{role: role} ->
        if role in allowed do
          conn
        else
          deny(conn)
        end

      _ ->
        deny(conn)
    end
  end

  defp deny(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(403, ~s|{"error":"forbidden","message":"Insufficient role"}|)
    |> halt()
  end
end
