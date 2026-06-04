defmodule BlennyExampleApp.Blenny.FormAuth do
  @moduledoc """
  Form-based auth module — sign-in, registration, avatar upload.

  Stores users in a configurable backend (`:memory` or `:dets`) and
  manages sessions via Phoenix cookies (no JWT dependency needed).

  ## Configuration

      config :blenny_ex, :form_auth_store, :memory   # default
      config :blenny_ex, :form_auth_store, :dets      # durable
  """

  use Blenny.Module
  import Plug.Conn
  import Phoenix.Controller, only: [html: 2, redirect: 2, json: 2]

  @store_key {__MODULE__, :user_store}

  # ── Blenny.Module callbacks ───────────────────────────────────────

  @impl true
  def name, do: "form-auth"

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
  def subscriptions, do: []

  @impl true
  def auth do
    [login_route: "/auth/signin"]
  end

  @impl true
  def initialize(_app_state) do
    store_type = Application.get_env(:blenny_ex, :form_auth_store, :memory)

    {user_mod, user_pid, blob_pid} =
      case store_type do
        :memory ->
          {:ok, u} = Blenny.Storage.Impl.InMemory.start_link([])
          {:ok, b} = Blenny.Storage.Impl.FSBlob.start_link(base_dir: "./data/blobs")
          {Blenny.Storage.Impl.InMemory, u, b}

        :dets ->
          {:ok, u} = Blenny.Storage.Impl.DETS.start_link(data_dir: "./data/form_auth")
          {:ok, b} = Blenny.Storage.Impl.FSBlob.start_link(base_dir: "./data/blobs")
          {Blenny.Storage.Impl.DETS, u, b}
      end

    :persistent_term.put(@store_key, {user_mod, user_pid, blob_pid})

    Blenny.AuthRegistry.register(%{
      module: __MODULE__,
      fetch_session: &__MODULE__.verify_request/1,
      login_route: "/auth/signin",
      stores: %{users: user_pid, blobs: blob_pid}
    })

    seed_admin(user_mod, user_pid)
    :ok
  end

  defp seed_admin(mod, pid) do
    case mod.find_by_username(pid, "admin") do
      nil ->
        hash = BlennyExampleApp.Blenny.FormAuth.Crypto.derive_key("admin123", "admin")

        mod.create_user(pid, %{
          username: "admin",
          password_hash: hash,
          display_name: "Admin",
          role: "admin"
        })

      _ ->
        :ok
    end
  end

  # ── Plug callbacks (Phoenix controller) ─────────────────────────

  @doc false
  def init(opts), do: opts

  @doc false
  def call(conn, action) when is_atom(action) do
    apply(__MODULE__, action, [conn, conn.params])
  end

  # ── AuthRegistry fetch_session ───────────────────────────────────

  def verify_request(conn) do
    case get_session(conn, "blenny_user_id") do
      nil -> nil
      id -> %Blenny.Auth{id: id, role: get_session(conn, "blenny_user_role")}
    end
  end

  # ── Route handlers ───────────────────────────────────────────────

  def render_sign_in(conn, _params) do
    token = Plug.CSRFProtection.get_csrf_token()
    html(conn, ui_sign_in(nil, token))
  end

  def handle_sign_in(conn, %{"username" => username, "password" => password}) do
    {mod, pid, _blob} = :persistent_term.get(@store_key)

    case mod.find_by_username(pid, username) do
      nil ->
        token = Plug.CSRFProtection.get_csrf_token()
        html(conn, ui_sign_in("Invalid username or password", token))

      user ->
        hash = BlennyExampleApp.Blenny.FormAuth.Crypto.derive_key(password, user.username)

        if user.password_hash == hash do
          redirect_to = Map.get(conn.params, "redirect_to", "/dashboard")

          conn
          |> put_session("blenny_user_id", user.id)
          |> put_session("blenny_user_role", user.role)
          |> put_session("blenny_user_display_name", user.display_name)
          |> configure_session(renew: true)
          |> redirect(to: redirect_to)
        else
          token = Plug.CSRFProtection.get_csrf_token()
          html(conn, ui_sign_in("Invalid username or password", token))
        end
    end
  end

  def render_register(conn, _params) do
    token = Plug.CSRFProtection.get_csrf_token()
    html(conn, ui_register(nil, token))
  end

  def handle_register(conn, %{"username" => username, "password" => password} = params) do
    display_name = Map.get(params, "display_name", "")

    cond do
      String.length(username) < 1 ->
        token = Plug.CSRFProtection.get_csrf_token()
        html(conn, ui_register("Username is required", token))

      String.length(password) < 8 ->
        token = Plug.CSRFProtection.get_csrf_token()
        html(conn, ui_register("Password must be at least 8 characters", token))

      String.length(display_name) < 1 ->
        token = Plug.CSRFProtection.get_csrf_token()
        html(conn, ui_register("Display name is required", token))

      true ->
        {mod, pid, _blob} = :persistent_term.get(@store_key)
        hash = BlennyExampleApp.Blenny.FormAuth.Crypto.derive_key(password, username)

        case mod.create_user(pid, %{
               username: username,
               password_hash: hash,
               display_name: display_name,
               role: "user"
             }) do
          {:ok, user} ->
            conn
            |> put_session("blenny_user_id", user.id)
            |> put_session("blenny_user_role", user.role)
            |> put_session("blenny_user_display_name", user.display_name)
            |> configure_session(renew: true)
            |> redirect(to: "/dashboard")

          {:error, :already_exists} ->
            token = Plug.CSRFProtection.get_csrf_token()
            html(conn, ui_register("Username already taken", token))
        end
    end
  end

  def handle_sign_out(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: "/")
  end

  def handle_avatar_upload(conn, %{"avatar" => _data}) do
    {_mod, _pid, blob_pid} = :persistent_term.get(@store_key)
    user = conn.assigns.blenny_auth
    # TODO: parse uploaded file and store via blob_pid
    # For now, return placeholder
    {:ok, key} = Blenny.Storage.Impl.FSBlob.set(blob_pid, "avatars", user.id, "", "image/png")

    {mod, pid, _blob} = :persistent_term.get(@store_key)
    mod.update_avatar_key(pid, user.id, key)

    json(conn, %{ok: true, key: key})
  end

  def handle_avatar_serve(conn, %{"user_id" => user_id}) do
    {mod, pid, blob_pid} = :persistent_term.get(@store_key)

    case mod.find_by_id(pid, user_id) do
      nil ->
        conn |> send_resp(404, "Not found") |> halt()

      %{avatar_key: nil} ->
        conn |> send_resp(404, "Not found") |> halt()

      _user ->
        case Blenny.Storage.Impl.FSBlob.get(blob_pid, "avatars", user_id) do
          {:ok, %{data: data, mime_type: mime}} ->
            conn
            |> put_resp_content_type(mime)
            |> send_resp(200, data)

          {:error, _reason} ->
            conn |> send_resp(404, "Not found") |> halt()
        end
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
