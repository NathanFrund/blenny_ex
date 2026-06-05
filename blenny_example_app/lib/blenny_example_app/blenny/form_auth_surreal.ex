defmodule BlennyExampleApp.Blenny.FormAuthSurreal do
  use Blenny.Module
  import Plug.Conn
  import Phoenix.Controller, only: [html: 2, redirect: 2, json: 2]
  require Logger

  @store_key {__MODULE__, :store}

  @impl true
  def name, do: "form-auth-surreal"

  @impl true
  def capabilities, do: ["auth"]

  @blenny_routes {:http, :get, "/auth/signin", __MODULE__, :render_sign_in}
  @blenny_routes {:http, :post, "/auth/signin", __MODULE__, :handle_sign_in}
  @blenny_routes {:http, :get, "/auth/register", __MODULE__, :render_register}
  @blenny_routes {:http, :post, "/auth/register", __MODULE__, :handle_register}
  @blenny_routes {:http, :post, "/auth/signout", __MODULE__, :handle_sign_out}
  @blenny_routes {:http, :post, "/auth/avatar", __MODULE__, :handle_avatar_upload, [auth: true]}
  @blenny_routes {:http, :get, "/avatars/:user_id", __MODULE__, :handle_avatar_serve}

  @impl true
  def routes, do: @blenny_routes

  @impl true
  def auth do
    [login_route: "/auth/signin"]
  end

  @impl true
  def initialize(_app_state) do
    surreal_opts =
      :blenny_example_app
      |> Application.get_env(:surrealdb, [])
      |> Keyword.put(:name, SurrealDB.Connection)

    conn =
      case DynamicSupervisor.start_child(
             Blenny.ModuleSupervisor,
             {SurrealDB, surreal_opts}
           ) do
        {:ok, _pid} ->
          case SurrealDB.Connection.wait_for_ready(SurrealDB.Connection) do
            :ok ->
              SurrealDB.Connection

            {:error, :timeout} ->
              Logger.warning("[FormAuthSurreal] Connection timeout")
              SurrealDB.Connection
          end

        {:error, reason} ->
          Logger.warning("[FormAuthSurreal] SurrealDB connection failed: #{inspect(reason)}")
          nil
      end

    {:ok, b} =
      DynamicSupervisor.start_child(
        Blenny.ModuleSupervisor,
        {Blenny.Storage.Impl.FSBlob, base_dir: "./data/blobs"}
      )

    if conn, do: init_schema(conn)

    bridge =
      if conn do
        case DynamicSupervisor.start_child(
               Blenny.ModuleSupervisor,
               {Blenny.SurrealDB.PublisherBridge,
                connection: conn, subscriptions: [%{table: "user", intent: :ui}]}
             ) do
          {:ok, pid} ->
            pid

          {:error, reason} ->
            Logger.warning("[FormAuthSurreal] PublisherBridge failed: #{inspect(reason)}")
            nil
        end
      end

    :persistent_term.put(@store_key, {conn, b, bridge})

    Blenny.AuthRegistry.register(%{
      module: __MODULE__,
      fetch_session: &__MODULE__.verify_request/1,
      login_route: "/auth/signin",
      stores: %{users: conn, blobs: b}
    })

    if conn, do: seed_admin(conn)
    :ok
  end

  defp init_schema(conn) do
    stmts = [
      "DEFINE TABLE IF NOT EXISTS user",
      "DEFINE FIELD uuid ON TABLE user TYPE uuid",
      "DEFINE FIELD IF NOT EXISTS username ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS password ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS display_name ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS role ON TABLE user TYPE string",
      "DEFINE FIELD IF NOT EXISTS avatar_key ON TABLE user TYPE option<string>",
      "DEFINE INDEX IF NOT EXISTS user_username ON TABLE user COLUMNS username UNIQUE"
    ]

    Enum.each(stmts, fn stmt ->
      case SurrealDB.query(conn, stmt) do
        {:ok, _} ->
          :ok

        {:error, reason} ->
          Logger.warning("[FormAuthSurreal] Schema setup warning: #{inspect(reason)}")
      end
    end)
  end

  defp seed_admin(conn) do
    case query_one(conn, "SELECT * FROM user WHERE username = 'admin'") do
      {:ok, _user} ->
        :ok

      {:error, :not_found} ->
        SurrealDB.query(
          conn,
          """
            CREATE user CONTENT {
              uuid: $uuid,
              username: 'admin',
              password: crypto::argon2::generate('admin123'),
              display_name: 'Admin',
              role: 'admin'
            }
          """,
          %{"uuid" => Blenny.Storage.UUID.generate()}
        )

        :ok

      {:error, _other} ->
        :ok
    end
  end

  def verify_request(conn) do
    case get_session(conn, "blenny_user_id") do
      nil -> nil
      id -> %Blenny.Auth{id: id, role: get_session(conn, "blenny_user_role")}
    end
  end

  # ── Route handlers ───────────────────────────────────────────────

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, action) when is_atom(action) do
    apply(__MODULE__, action, [conn, conn.params])
  end

  def render_sign_in(conn, _params) do
    token = Plug.CSRFProtection.get_csrf_token()
    html(conn, ui_sign_in(nil, token))
  end

  def handle_sign_in(conn, %{"username" => username, "password" => password}) do
    {conn_pid, _blob, _bridge} = :persistent_term.get(@store_key)

    token = Plug.CSRFProtection.get_csrf_token()

    if conn_pid == nil do
      html(conn, ui_sign_in("Database unavailable", token))
    else
      case query_one(
             conn_pid,
             """
               SELECT * FROM user
               WHERE username = $username
                 AND crypto::argon2::compare(password, $password)
             """,
             %{"username" => username, "password" => password}
           ) do
        {:ok, user} ->
          conn
          |> put_session("blenny_user_id", user["uuid"])
          |> put_session("blenny_user_role", user["role"])
          |> put_session("blenny_user_display_name", user["display_name"])
          |> configure_session(renew: true)
          |> redirect(to: Map.get(conn.params, "redirect_to", "/dashboard"))

        {:error, :not_found} ->
          html(conn, ui_sign_in("Invalid username or password", token))

        {:error, reason} ->
          Logger.warning("[FormAuthSurreal] Sign-in error: #{inspect(reason)}")
          html(conn, ui_sign_in("Unable to sign in. Please try again.", token))
      end
    end
  end

  def render_register(conn, _params) do
    token = Plug.CSRFProtection.get_csrf_token()
    html(conn, ui_register(nil, token))
  end

  def handle_register(conn, %{"username" => username, "password" => password} = params) do
    display_name = Map.get(params, "display_name", "")
    token = Plug.CSRFProtection.get_csrf_token()

    {conn_pid, _blob, _bridge} = :persistent_term.get(@store_key)

    if conn_pid == nil do
      html(conn, ui_register("Database unavailable", token))
    else
      cond do
        String.length(username) < 1 ->
          html(conn, ui_register("Username is required", token))

        String.length(password) < 8 ->
          html(conn, ui_register("Password must be at least 8 characters", token))

        String.length(display_name) < 1 ->
          html(conn, ui_register("Display name is required", token))

        true ->
          case query_one(conn_pid, "SELECT * FROM user WHERE username = $username", %{
                 "username" => username
               }) do
            {:ok, _existing} ->
              html(conn, ui_register("Username already taken", token))

            {:error, :not_found} ->
              uuid = Blenny.Storage.UUID.generate()

              case SurrealDB.query(
                     conn_pid,
                     """
                       CREATE user CONTENT {
                         uuid: $uuid,
                         username: $username,
                         password: crypto::argon2::generate($password),
                         display_name: $display_name,
                         role: 'user'
                       }
                     """,
                     %{
                       "uuid" => uuid,
                       "username" => username,
                       "password" => password,
                       "display_name" => display_name
                     }
                   ) do
                {:ok, _json} ->
                  conn
                  |> put_session("blenny_user_id", uuid)
                  |> put_session("blenny_user_role", "user")
                  |> put_session("blenny_user_display_name", display_name)
                  |> configure_session(renew: true)
                  |> redirect(to: "/dashboard")

                {:error, reason} ->
                  html(conn, ui_register("Registration failed: #{inspect(reason)}", token))
              end

            {:error, reason} ->
              Logger.warning(
                "[FormAuthSurreal] Schema error, re-initializing: #{inspect(reason)}"
              )

              init_schema(conn_pid)

              case query_one(conn_pid, "SELECT * FROM user WHERE username = $username", %{
                     "username" => username
                   }) do
                {:ok, _existing} ->
                  html(conn, ui_register("Username already taken", token))

                {:error, :not_found} ->
                  uuid = Blenny.Storage.UUID.generate()

                  case SurrealDB.query(
                         conn_pid,
                         """
                           CREATE user CONTENT {
                             uuid: $uuid,
                             username: $username,
                             password: crypto::argon2::generate($password),
                             display_name: $display_name,
                             role: 'user'
                           }
                         """,
                         %{
                           "uuid" => uuid,
                           "username" => username,
                           "password" => password,
                           "display_name" => display_name
                         }
                       ) do
                    {:ok, _json} ->
                      conn
                      |> put_session("blenny_user_id", uuid)
                      |> put_session("blenny_user_role", "user")
                      |> put_session("blenny_user_display_name", display_name)
                      |> configure_session(renew: true)
                      |> redirect(to: "/dashboard")

                    {:error, reason} ->
                      html(conn, ui_register("Registration failed: #{inspect(reason)}", token))
                  end

                {:error, reason} ->
                  html(conn, ui_register("Registration failed: #{inspect(reason)}", token))
              end
          end
      end
    end
  end

  def handle_sign_out(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  def handle_avatar_upload(conn, %{"avatar" => _data}) do
    {conn_pid, blob_pid, _bridge} = :persistent_term.get(@store_key)
    user = conn.assigns.blenny_auth

    {:ok, key} = Blenny.Storage.Impl.FSBlob.set(blob_pid, "avatars", user.id, "", "image/png")

    if conn_pid do
      SurrealDB.query(conn_pid, "UPDATE user MERGE { avatar_key: $key } WHERE uuid = $uuid", %{
        "key" => key,
        "uuid" => user.id
      })
    end

    json(conn, %{ok: true, key: key})
  end

  def handle_avatar_serve(conn, %{"user_id" => user_id}) do
    {conn_pid, blob_pid, _bridge} = :persistent_term.get(@store_key)

    if conn_pid == nil do
      conn |> send_resp(503, "Database unavailable") |> halt()
    else
      case query_one(conn_pid, "SELECT * FROM user WHERE uuid = $uuid", %{"uuid" => user_id}) do
        {:ok, %{"avatar_key" => nil}} ->
          conn |> send_resp(404, "Not found") |> halt()

        {:ok, _user} ->
          case Blenny.Storage.Impl.FSBlob.get(blob_pid, "avatars", user_id) do
            {:ok, %{data: data, mime_type: mime}} ->
              conn
              |> put_resp_content_type(mime)
              |> send_resp(200, data)

            {:error, _reason} ->
              conn |> send_resp(404, "Not found") |> halt()
          end

        {:error, :not_found} ->
          conn |> send_resp(404, "Not found") |> halt()

        {:error, reason} ->
          Logger.warning("[FormAuthSurreal] Avatar lookup error: #{inspect(reason)}")
          conn |> send_resp(503, "Database unavailable") |> halt()
      end
    end
  end

  # ── SurrealQL helpers ────────────────────────────────────────────

  defp query_one(conn, sql, vars \\ %{}) do
    case SurrealDB.query(conn, sql, vars) do
      {:ok, json} ->
        case json["result"] do
          [%{"status" => "OK", "result" => [record]}] -> {:ok, record}
          [%{"status" => "OK", "result" => []}] -> {:error, :not_found}
          [%{"status" => "ERR", "detail" => detail}] -> {:error, detail}
          _ -> {:error, :unexpected_result}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  # ── UI helpers ────────────────────────────────────────────────────

  defp ui_sign_in(error, csrf_token) do
    err =
      if error do
        ~s|<p class="text-red-500 text-sm mt-1">#{e(error)}</p>|
      else
        ""
      end

    ~s"""
    <div class="min-h-screen flex items-center justify-center bg-base-200">
      <div class="card w-96 bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl font-bold justify-center">Sign In</h2>
          <form method="post" action="/auth/signin">
            <input type="hidden" name="_csrf_token" value="#{csrf_token}" />
            <label class="form-control w-full mb-3">
              <span class="label-text">Username</span>
              <input type="text" name="username" required class="input input-bordered w-full" />
            </label>
            <label class="form-control w-full mb-3">
              <span class="label-text">Password</span>
              <input type="password" name="password" required class="input input-bordered w-full" />
            </label>
            #{err}
            <button type="submit" class="btn btn-primary w-full mt-2">Sign In</button>
          </form>
          <p class="text-center mt-4 text-sm">
            <a href="/auth/register" class="link link-primary">Create an account</a>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp ui_register(error, csrf_token) do
    err =
      if error do
        ~s|<p class="text-red-500 text-sm mt-1">#{e(error)}</p>|
      else
        ""
      end

    ~s"""
    <div class="min-h-screen flex items-center justify-center bg-base-200">
      <div class="card w-96 bg-base-100 shadow-xl">
        <div class="card-body">
          <h2 class="card-title text-2xl font-bold justify-center">Register</h2>
          <form method="post" action="/auth/register">
            <input type="hidden" name="_csrf_token" value="#{csrf_token}" />
            <label class="form-control w-full mb-3">
              <span class="label-text">Username</span>
              <input type="text" name="username" required class="input input-bordered w-full" />
            </label>
            <label class="form-control w-full mb-3">
              <span class="label-text">Display Name</span>
              <input type="text" name="display_name" required class="input input-bordered w-full" />
            </label>
            <label class="form-control w-full mb-3">
              <span class="label-text">Password</span>
              <input type="password" name="password" required class="input input-bordered w-full" />
            </label>
            #{err}
            <button type="submit" class="btn btn-primary w-full mt-2">Register</button>
          </form>
          <p class="text-center mt-4 text-sm">
            <a href="/auth/signin" class="link link-primary">Already have an account?</a>
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp e(str) when is_binary(str) do
    str
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace(">", "&gt;")
    |> String.replace(~S("), "&#34;")
    |> String.replace(~S('), "&#39;")
  end
end
